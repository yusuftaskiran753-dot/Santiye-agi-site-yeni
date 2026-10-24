// ════════════════════════════════════════════════════════════════════════
//  Şantiye Ağı · Mağaza satın alım doğrulama (Supabase Edge Function)
//
//  Uygulama, Google Play / App Store'dan bir satın alma aldığında bu
//  fonksiyonu çağırır. Fonksiyon makbuzu doğrudan mağazanın sunucusuna
//  sorar; geçerliyse Premium süresini veya kredi bakiyesini veritabanına
//  yazar. Böylece kimse sahte satın alma ile Premium/kredi elde edemez.
//
//  Gerekli gizli anahtarlar (Supabase → Edge Functions → Secrets):
//    ANDROID_PACKAGE_NAME          ör. com.santiyeagi.santiye_agi
//    GOOGLE_SERVICE_ACCOUNT_JSON   Play Console'a bağlı servis hesabının JSON anahtarı (tamamı)
//    APPLE_BUNDLE_ID               ör. com.santiyeagi.santiyeAgi
//    APPLE_IAP_ISSUER_ID           App Store Connect → Kullanıcılar ve Erişim → Entegrasyonlar → Uygulama İçi Satın Alma
//    APPLE_IAP_KEY_ID              aynı sayfadaki anahtar kimliği
//    APPLE_IAP_PRIVATE_KEY         indirilen .p8 dosyasının içeriği (BEGIN/END satırları dahil)
//  SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY Supabase tarafından otomatik verilir.
// ════════════════════════════════════════════════════════════════════════

import { createClient } from 'jsr:@supabase/supabase-js@2';

// Ürün kimlikleri uygulamadaki lib/config.dart ile birebir aynı olmalıdır.
const PREMIUM_PRODUCTS: Record<string, string> = {
  santiye_premium_aylik: 'monthly',
  santiye_premium_yillik: 'yearly',
};
const CREDIT_PRODUCTS: Record<string, number> = {
  santiye_kredi_5: 5,
  santiye_kredi_15: 15,
  santiye_kredi_40: 40,
};

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

type Json = Record<string, unknown>;

function reply(body: Json, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new VerifyError('CONFIG', `Eksik gizli anahtar: ${name}`);
  return value;
}

class VerifyError extends Error {
  constructor(public code: string, message: string) {
    super(message);
  }
}

/** Mağaza yanıtındaki hatayı sınıflandırır: geçersiz işlem (kalıcı) mi, geçici/yapılandırma sorunu mu? */
function storeError(res: Response, message: string): VerifyError {
  // 400/404/410: işlem kimliği geçersiz veya bulunamadı → kalıcı ret.
  // 401/403: servis hesabı izni / anahtar sorunu, 429/5xx: geçici → uygulama daha sonra yeniden dener.
  if (res.status === 400 || res.status === 404 || res.status === 410) return new VerifyError('INVALID', message);
  return new VerifyError('SERVER', `${message} (HTTP ${res.status})`);
}

// ───────────── Kodlama yardımcıları ─────────────

function base64UrlFromBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlFromString(text: string): string {
  return base64UrlFromBytes(new TextEncoder().encode(text));
}

function bytesFromBase64Url(text: string): Uint8Array {
  const normalized = text.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out.buffer;
}

function decodeJwsPayload(jws: string): Json {
  const parts = jws.split('.');
  if (parts.length !== 3) throw new VerifyError('INVALID', 'Geçersiz işlem verisi');
  return JSON.parse(new TextDecoder().decode(bytesFromBase64Url(parts[1]))) as Json;
}

async function signJwt(
  header: Json,
  payload: Json,
  key: CryptoKey,
  algorithm: AlgorithmIdentifier | EcdsaParams,
): Promise<string> {
  const unsigned = `${base64UrlFromString(JSON.stringify(header))}.${base64UrlFromString(JSON.stringify(payload))}`;
  const signature = await crypto.subtle.sign(algorithm, key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64UrlFromBytes(new Uint8Array(signature))}`;
}

// ───────────── Google Play ─────────────

async function googleAccessToken(): Promise<string> {
  const account = JSON.parse(env('GOOGLE_SERVICE_ACCOUNT_JSON')) as { client_email: string; private_key: string };
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    key,
    { name: 'RSASSA-PKCS1-v1_5' },
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  const data = (await res.json()) as Json;
  if (!res.ok || typeof data.access_token !== 'string') {
    throw new VerifyError('CONFIG', 'Google servis hesabı ile oturum açılamadı');
  }
  return data.access_token;
}

interface Verified {
  kind: 'premium' | 'credits';
  purchaseKey: string;
  plan?: string;
  expiresAt?: Date;
  credits?: number;
  accountId?: string;
}

async function verifyGoogle(productId: string, token: string): Promise<Verified> {
  const pkg = env('ANDROID_PACKAGE_NAME');
  const access = await googleAccessToken();
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(pkg)}/purchases`;
  const headers = { Authorization: `Bearer ${access}` };

  if (PREMIUM_PRODUCTS[productId]) {
    const res = await fetch(`${base}/subscriptionsv2/tokens/${encodeURIComponent(token)}`, { headers });
    if (!res.ok) throw storeError(res, 'Abonelik Google Play tarafından doğrulanamadı');
    const data = (await res.json()) as Json;
    const state = String(data.subscriptionState ?? '');
    const valid = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'];
    const items = (data.lineItems as Array<{ productId?: string; expiryTime?: string }> | undefined) ?? [];
    let expiry = 0;
    for (const item of items) {
      if (item.productId === productId && item.expiryTime) expiry = Math.max(expiry, Date.parse(item.expiryTime));
    }
    if (!valid.includes(state) || !expiry || expiry < Date.now()) {
      throw new VerifyError('EXPIRED', 'Aboneliğin süresi dolmuş');
    }
    const ids = (data.externalAccountIdentifiers as Json | undefined) ?? {};
    return {
      kind: 'premium',
      purchaseKey: token,
      plan: PREMIUM_PRODUCTS[productId],
      expiresAt: new Date(expiry),
      accountId: typeof ids.obfuscatedExternalAccountId === 'string' ? ids.obfuscatedExternalAccountId : undefined,
    };
  }

  const credits = CREDIT_PRODUCTS[productId];
  if (!credits) throw new VerifyError('UNKNOWN_PRODUCT', 'Tanımsız ürün');
  const res = await fetch(`${base}/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`, { headers });
  if (!res.ok) throw storeError(res, 'Satın alma Google Play tarafından doğrulanamadı');
  const data = (await res.json()) as Json;
  if (Number(data.purchaseState ?? -1) !== 0) throw new VerifyError('INVALID', 'Ödeme tamamlanmamış');
  const rawQuantity = Number(data.quantity ?? 1);
  const quantity = Number.isSafeInteger(rawQuantity) && rawQuantity > 0 && rawQuantity <= 10000 ? rawQuantity : 1;
  return {
    kind: 'credits',
    purchaseKey: token,
    credits: credits * quantity,
    accountId: typeof data.obfuscatedExternalAccountId === 'string' ? data.obfuscatedExternalAccountId : undefined,
  };
}

// ───────────── App Store ─────────────

async function appleToken(): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(env('APPLE_IAP_PRIVATE_KEY')),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const now = Math.floor(Date.now() / 1000);
  return signJwt(
    { alg: 'ES256', kid: env('APPLE_IAP_KEY_ID'), typ: 'JWT' },
    { iss: env('APPLE_IAP_ISSUER_ID'), iat: now, exp: now + 1200, aud: 'appstoreconnect-v1', bid: env('APPLE_BUNDLE_ID') },
    key,
    { name: 'ECDSA', hash: 'SHA-256' },
  );
}

async function fetchAppleTransaction(transactionId: string): Promise<Json> {
  const token = await appleToken();
  const hosts = ['https://api.storekit.itunes.apple.com', 'https://api.storekit-sandbox.itunes.apple.com'];
  for (const host of hosts) {
    const res = await fetch(`${host}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) continue; // Üretimde yoksa test (sandbox) ortamına bak.
    if (!res.ok) throw storeError(res, 'Satın alma App Store tarafından doğrulanamadı');
    const data = (await res.json()) as Json;
    if (typeof data.signedTransactionInfo !== 'string') throw new VerifyError('INVALID', 'İşlem bulunamadı');
    return decodeJwsPayload(data.signedTransactionInfo);
  }
  throw new VerifyError('INVALID', 'İşlem bulunamadı');
}

async function verifyApple(productId: string, transactionId: string): Promise<Verified> {
  const tx = await fetchAppleTransaction(transactionId);
  if (tx.bundleId !== env('APPLE_BUNDLE_ID')) throw new VerifyError('INVALID', 'Uygulama kimliği uyuşmuyor');
  if (tx.productId !== productId) throw new VerifyError('INVALID', 'Ürün uyuşmuyor');
  if (tx.revocationDate) throw new VerifyError('REVOKED', 'Satın alma iade edilmiş');
  const accountId = typeof tx.appAccountToken === 'string' ? tx.appAccountToken : undefined;

  if (PREMIUM_PRODUCTS[productId]) {
    const expires = Number(tx.expiresDate ?? 0);
    if (!expires || expires < Date.now()) throw new VerifyError('EXPIRED', 'Aboneliğin süresi dolmuş');
    return {
      kind: 'premium',
      purchaseKey: String(tx.originalTransactionId ?? transactionId),
      plan: PREMIUM_PRODUCTS[productId],
      expiresAt: new Date(expires),
      accountId,
    };
  }
  const credits = CREDIT_PRODUCTS[productId];
  if (!credits) throw new VerifyError('UNKNOWN_PRODUCT', 'Tanımsız ürün');
  const rawQuantity = Number(tx.quantity ?? 1);
  const quantity = Number.isSafeInteger(rawQuantity) && rawQuantity > 0 && rawQuantity <= 10000 ? rawQuantity : 1;
  return { kind: 'credits', purchaseKey: String(tx.transactionId ?? transactionId), credits: credits * quantity, accountId };
}

// ───────────── Giriş noktası ─────────────

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return reply({ ok: false, error: 'METHOD' }, 405);

  try {
    const url = env('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? env('SERVICE_ROLE_KEY');
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data: auth, error: authError } = await admin.auth.getUser(jwt);
    if (authError || !auth?.user) return reply({ ok: false, error: 'AUTH' }, 401);
    const userId = auth.user.id;

    let body: Json;
    try {
      body = (await req.json()) as Json;
    } catch {
      return reply({ ok: false, error: 'BAD_INPUT' }, 400);
    }
    const platform = String(body.platform ?? '');
    const productId = String(body.productId ?? '');
    const token = String(body.token ?? '');
    if (!productId || !token || (platform !== 'android' && platform !== 'ios')) {
      return reply({ ok: false, error: 'BAD_INPUT' }, 400);
    }

    const verified = platform === 'android' ? await verifyGoogle(productId, token) : await verifyApple(productId, token);

    // Satın alma başka bir uygulama hesabı adına yapılmışsa:
    // kredi aktarılmaz; abonelik ise ödeyen mağaza hesabını izler (taşınır).
    if (verified.kind === 'credits' && verified.accountId && verified.accountId !== userId) {
      return reply({ ok: false, error: 'ACCOUNT_MISMATCH' }, 409);
    }

    if (verified.kind === 'credits') {
      // Satın alma idempotency kaydı + bakiye + defter satırı tek RPC/transaction.
      // Böylece kayıt başarılı olup kredi artışı başarısız kalamaz.
      const amount = verified.credits ?? 0;
      if (!Number.isSafeInteger(amount) || amount <= 0) {
        throw new VerifyError('INVALID', 'Satın alma kredi miktarı geçersiz');
      }
      const { data: creditResult, error: creditError } = await admin.rpc('record_and_grant_credit_purchase', {
        p_platform: platform,
        p_key: verified.purchaseKey,
        p_user: userId,
        p_product: productId,
        p_amount: amount,
      });
      if (creditError) throw new Error(creditError.message);
      if (creditResult === 'other_user') return reply({ ok: false, error: 'ALREADY_USED' }, 409);
      if (creditResult !== 'granted' && creditResult !== 'already_granted') {
        throw new Error('Beklenmeyen kredi satın alma sonucu');
      }
      const { data: wallet, error: walletError } = await admin.from('credit_wallets').select('balance').eq('user_id', userId).maybeSingle();
      if (walletError) throw new Error(walletError.message);
      return reply({ ok: true, kind: 'credits', credits: (wallet as { balance?: number } | null)?.balance ?? 0 });
    }

    const { data: recorded, error: recordError } = await admin.rpc('record_store_purchase', {
      p_platform: platform,
      p_key: verified.purchaseKey,
      p_user: userId,
      p_product: productId,
      p_kind: verified.kind,
    });
    if (recordError) throw new Error(recordError.message);

    if (recorded === 'other_user') {
      const { error } = await admin.rpc('transfer_store_purchase', {
        p_platform: platform,
        p_key: verified.purchaseKey,
        p_user: userId,
      });
      if (error) throw new Error(error.message);
    }
    const { data: until, error: premiumError } = await admin.rpc('set_premium', {
      p_user: userId,
      p_until: verified.expiresAt?.toISOString(),
      p_plan: verified.plan ?? '',
      p_platform: platform,
    });
    if (premiumError) throw new Error(premiumError.message);
    return reply({ ok: true, kind: 'premium', premium_until: until });
  } catch (e) {
    if (e instanceof VerifyError) {
      const status = e.code === 'CONFIG' ? 500 : 422;
      return reply({ ok: false, error: e.code, message: e.message }, status);
    }
    console.error('verify-purchase', e);
    return reply({ ok: false, error: 'SERVER', message: String(e) }, 500);
  }
});
