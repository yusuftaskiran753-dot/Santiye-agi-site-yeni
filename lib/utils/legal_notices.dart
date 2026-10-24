/// Yorum ve mesaj ekranlarında gösterilen kısa yasal uyarılar (iskelet metin).
///
/// TODO: Avukat onaylı nihai metin ve legal/ sayfalarına bağlantı.
class LegalNotices {
  const LegalNotices._();

  static const comments =
      'Yorumlar kamuya açıktır. Hakaret, iftira ve karalama 5237 sayılı TCK '
      'ile KVKK kapsamında sorumluluk doğurur. Küfürlü içerik otomatik elenir. '
      'Olumsuz yorum için birlikte çalışma kanıtı gerekir; kanıtsız olumsuz '
      'yorum yayına çıkmaz, incelemede bekler. Uygulama aracıdır, taraflar '
      'kendi beyanlarından sorumludur.';

  static const messages =
      'Mesajlar yalnızca siz ve karşı taraf arasındadır. Dolandırıcılık, '
      'tehdit, hakaret ve kişisel verilerin izinsiz paylaşımı yasaktır. '
      'Telefon numarası, onaylanmadan profilde veya sohbette gösterilmez. '
      'Şüpheli içerikte şikâyet edin. Uygulama ödemeye aracılık etmez.';

  static const tender =
      'İhale bu uygulamada duyuru ve teklif toplama içindir. Sözleşme, '
      'ödeme ve işin yapılması taraflar arasında, uygulamadan bağımsızdır.';

  static const block =
      'Engelleme gerekçesi yalnızca güvenlik kaydı içindir; karşı tarafa '
      'gösterilmez. Asılsız veya kötü niyetli gerekçe şikâyet konusu olabilir.';

  // ───────────── Her işlemde gösterilen kısa uyarı ─────────────

  /// Yorum, mesaj, gönderi, teklif ve engelleme dâhil her işlemde görünür.
  static const everyAction =
      'Mesajlar 24 saat içinde silinir, hakaret yasaktır.';

  static const workedTogether =
      'Bu kişiyle daha önce çalıştıysanız "Evet" deyin. Çalışmadıysanız '
      '"Hayır" deyip kanıt (fotoğraf veya açıklama) ekleyin; kanıtsız yorum '
      'yayına çıkmaz.';

  static const bid =
      'Teklifinizin yanındaki açıklama zorunludur. Telefon numaranız, ihaleyi '
      'açan onaylamadan kimseye gösterilmez.';

  static const phoneHidden =
      'Telefon numaraları, ihaleyi açan teklifi onaylayana kadar iki tarafa '
      'da gizlidir.';

  static const award =
      'Kazanan teklifi seçtiğinizde ihale kapanır. Sözleşme ve ödeme '
      'taraflar arasındadır; uygulama ödemeye aracılık etmez.';

  static const blockEvidence =
      'Engellemek için bir sebep seçmeli ve kanıt fotoğrafı eklemelisiniz. '
      'Kanıt yalnızca bu cihazdaki güvenlik kaydında tutulur, karşı tarafa '
      'gösterilmez.';

  static const post =
      'Paylaşımlar kamuya açıktır; küfür, hakaret ve iftira yayınlanmaz.';

  /// Profil, kapak, gönderi ve hikaye fotoğrafları için (KVKK).
  static const photo =
      'Fotoğraflar kişisel veridir. Yalnızca kendinize ait veya izin aldığınız '
      'fotoğrafları paylaşın; başkasının yüzünü izinsiz yayımlamayın. '
      'Fotoğraflarınız bu cihazda tutulur, istediğiniz zaman kaldırabilirsiniz.';

  static const story =
      'Hikayeler 24 saat sonra otomatik silinir. Hakaret, tehdit ve izinsiz '
      'kişisel veri içeren hikaye paylaşmayın.';

  /// KVKK aydınlatma metnine yönlendiren kısa not.
  static const kvkk =
      'Kişisel verileriniz 6698 sayılı KVKK kapsamında işlenir. Ayrıntı için '
      'KVKK Aydınlatma Metni\'ni okuyabilirsiniz.';

  static const responsibility =
      'Paylaştığınız içeriğin (yazı, fotoğraf, yorum, teklif) hukuki '
      'sorumluluğu size aittir. Uygulama yalnızca aracıdır; şikâyet edilen '
      'içerik kaldırılabilir, hesap kısıtlanabilir.';

  /// İşleme özel metnin önüne her zaman [everyAction] eklenir.
  static String withEveryAction(String specific) =>
      specific.isEmpty ? everyAction : '$everyAction $specific';
}
