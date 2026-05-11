import 'package:flutter/material.dart';
import '../../config/theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgSecondary,
      appBar: AppBar(
        backgroundColor: context.bgPrimary,
        surfaceTintColor: Colors.transparent,
        title: const Text('Gizlilik Politikası'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.borderColor, height: 0.5),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, 'Gizlilik Politikası'),
            _subtitle(context, 'Öğretimsayfam - MaariFx'),
            const SizedBox(height: 16),
            _body(context,
                'Öğretimsayfam ("Şirket", "biz", "bizim") olarak, Maarifx uygulaması ve web sitesi ("Hizmet") aracılığıyla sunduğumuz hizmetlerde kişisel verilerinizin korunmasına büyük önem veriyoruz. Bu Gizlilik Politikası, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") ve ilgili mevzuat kapsamında kişisel verilerinizin nasıl toplandığını, işlendiğini, saklandığını ve korunduğunu açıklamaktadır.'),
            const SizedBox(height: 8),
            _body(context,
                'Hizmetimizi kullanarak bu Gizlilik Politikası\'nda belirtilen uygulamaları kabul etmiş sayılırsınız.'),

            const SizedBox(height: 24),
            _sectionHeader(context, '1. Veri Sorumlusu'),
            _bullet(context, 'Veri Sorumlusu: Öğretimsayfam'),
            _bullet(context, 'Web Sitesi: ogretimsayfam.com'),
            _bullet(context, 'Ürün Web Sitesi: maarifx.com'),
            _bullet(context, 'İletişim E-postası: destek@ogretimsayfam.com'),

            const SizedBox(height: 24),
            _sectionHeader(context, '2. Toplanan Kişisel Veriler'),
            _body(context,
                'Hizmetimizi kullanmanız sırasında aşağıdaki kişisel verileriniz toplanmaktadır:'),
            const SizedBox(height: 12),
            _subsectionHeader(context, '2.1. Kimlik ve İletişim Bilgileri'),
            _bullet(context, 'Ad ve soyad'),
            _bullet(context, 'E-posta adresi'),
            _bullet(context, 'Şifre (şifrelenmiş olarak saklanır)'),
            const SizedBox(height: 12),
            _subsectionHeader(context, '2.2. Kullanım Verileri'),
            _bullet(context, 'Gönderilen sorular ve soru metinleri'),
            _bullet(context, 'Yüklenen soru görselleri'),
            _bullet(context, 'Yapay zeka asistanı tarafından üretilen yanıtlar'),
            _bullet(context, 'Hizmet kullanım geçmişi'),

            const SizedBox(height: 24),
            _sectionHeader(context, '3. Kişisel Verilerin İşlenme Amaçları'),
            _body(context,
                'Kişisel verileriniz aşağıdaki amaçlarla işlenmektedir:'),
            _bullet(context,
                'Hesap oluşturma ve kimlik doğrulama işlemlerinin gerçekleştirilmesi'),
            _bullet(context,
                'Yapay zeka destekli eğitim hizmetinin sunulması'),
            _bullet(context, 'Sorularınızın işlenmesi ve yanıtlanması'),
            _bullet(context,
                'Hizmet kalitesinin artırılması ve geliştirilmesi'),
            _bullet(context, 'Kullanıcı deneyiminin iyileştirilmesi'),
            _bullet(context,
                'Teknik sorunların tespiti ve giderilmesi'),
            _bullet(context,
                'Yasal yükümlülüklerin yerine getirilmesi'),
            _bullet(context, 'Hizmet güvenliğinin sağlanması'),

            const SizedBox(height: 24),
            _sectionHeader(context,
                '4. Kişisel Verilerin İşlenmesinin Hukuki Sebepleri'),
            _body(context,
                'Kişisel verileriniz, KVKK\'nın 5. maddesi kapsamında aşağıdaki hukuki sebeplere dayanılarak işlenmektedir:'),
            _bullet(context,
                'Bir sözleşmenin kurulması veya ifasıyla doğrudan ilgili olması (Hizmet sözleşmesi)'),
            _bullet(context,
                'Veri sorumlusunun hukuki yükümlülüğünü yerine getirebilmesi'),
            _bullet(context,
                'Veri sorumlusunun meşru menfaatleri için zorunlu olması'),
            _bullet(context,
                'Açık rızanızın bulunması (gerekli hallerde)'),

            const SizedBox(height: 24),
            _sectionHeader(context,
                '5. Kişisel Verilerin Saklanması ve Güvenliği'),
            _subsectionHeader(context, '5.1. Veri Saklama Konumları'),
            _body(context,
                'Kişisel verileriniz aşağıdaki lokasyonlarda güvenli bir şekilde saklanmaktadır:'),
            _bullet(context,
                'Contabo VDS (Sanal Özel Sunucu) sistemleri'),
            _bullet(context, 'Şirketimize ait yerel sunucu sistemleri'),
            const SizedBox(height: 12),
            _subsectionHeader(context, '5.2. Veri Saklama Süresi'),
            _bullet(context,
                'Kişisel verileriniz, hesabınız aktif olduğu sürece saklanır.'),
            _bullet(context,
                'Hesap silme talebinde bulunmanız halinde, verileriniz güvenlik amaçlı olarak 15 (on beş) gün süreyle tutulur ve bu sürenin sonunda kalıcı olarak silinir.'),
            _bullet(context,
                'Yasal zorunluluklar gerektirdiği hallerde, ilgili mevzuatta öngörülen süreler boyunca veriler saklanabilir.'),
            const SizedBox(height: 12),
            _subsectionHeader(context, '5.3. Güvenlik Önlemleri'),
            _body(context,
                'Kişisel verilerinizin güvenliğini sağlamak için aşağıdaki teknik ve idari tedbirler uygulanmaktadır:'),
            _bullet(context,
                'Şifrelerin kriptografik yöntemlerle (hash) saklanması'),
            _bullet(context,
                'SSL/TLS şifreleme protokollerinin kullanılması'),
            _bullet(context,
                'Yetkisiz erişime karşı güvenlik duvarı ve erişim kontrolleri'),
            _bullet(context,
                'Düzenli güvenlik güncellemeleri ve denetimleri'),
            _bullet(context,
                'Veri erişiminin yalnızca yetkili personel ile sınırlandırılması'),

            const SizedBox(height: 24),
            _sectionHeader(context, '6. Kişisel Verilerin Aktarılması'),
            _body(context,
                'Kişisel verileriniz, aşağıda belirtilen taraflarla ve amaçlarla sınırlı olarak paylaşılabilir:'),
            _subsectionHeader(context, '6.1. Hizmet Sağlayıcılar'),
            _bullet(context,
                'Contabo GmbH - Sunucu altyapı hizmetleri'),
            const SizedBox(height: 12),
            _subsectionHeader(context, '6.2. Yasal Zorunluluklar'),
            _bullet(context,
                'Yetkili kamu kurum ve kuruluşları (yasal talep halinde)'),
            _bullet(context,
                'Adli merciler (mahkeme kararı veya yasal zorunluluk halinde)'),
            const SizedBox(height: 12),
            _body(context,
                'Önemli: Kişisel verileriniz, yukarıda belirtilen durumlar dışında üçüncü taraflarla paylaşılmaz, satılmaz veya kiralanmaz.',
                bold: true),

            const SizedBox(height: 24),
            _sectionHeader(context,
                '7. Kullanıcı Hakları (KVKK Madde 11)'),
            _body(context,
                'KVKK\'nın 11. maddesi kapsamında aşağıdaki haklara sahipsiniz:'),
            _bullet(context,
                'a) Kişisel verilerinizin işlenip işlenmediğini öğrenme'),
            _bullet(context,
                'b) Kişisel verileriniz işlenmişse buna ilişkin bilgi talep etme'),
            _bullet(context,
                'c) Kişisel verilerinizin işlenme amacını ve bunların amacına uygun kullanılıp kullanılmadığını öğrenme'),
            _bullet(context,
                'd) Yurt içinde veya yurt dışında kişisel verilerinizin aktarıldığı üçüncü kişileri bilme'),
            _bullet(context,
                'e) Kişisel verilerinizin eksik veya yanlış işlenmiş olması halinde bunların düzeltilmesini isteme'),
            _bullet(context,
                'f) KVKK\'nın 7. maddesinde öngörülen şartlar çerçevesinde kişisel verilerinizin silinmesini veya yok edilmesini isteme'),
            _bullet(context,
                'g) (e) ve (f) bentleri uyarınca yapılan işlemlerin, kişisel verilerinizin aktarıldığı üçüncü kişilere bildirilmesini isteme'),
            _bullet(context,
                'h) İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme'),
            _bullet(context,
                'i) Kişisel verilerinizin kanuna aykırı olarak işlenmesi sebebiyle zarara uğramanız halinde zararın giderilmesini talep etme'),
            const SizedBox(height: 8),
            _body(context,
                'Bu haklarınızı kullanmak için destek@ogretimsayfam.com adresine e-posta gönderebilir veya yazılı başvuru yapabilirsiniz.'),

            const SizedBox(height: 24),
            _sectionHeader(context, '8. Hesap Silme'),
            _body(context,
                'Hesabınızı ve kişisel verilerinizi silmek istemeniz halinde:'),
            _bullet(context,
                'Uygulama üzerinden hesap silme talebinde bulunabilirsiniz.'),
            _bullet(context,
                'destek@ogretimsayfam.com adresine e-posta göndererek talepte bulunabilirsiniz.'),
            const SizedBox(height: 8),
            _body(context, 'Silme talebinizin ardından:'),
            _bullet(context,
                'Tüm kişisel verileriniz sistemlerimizden kaldırılacaktır.'),
            _bullet(context,
                'Güvenlik ve kötüye kullanımı önleme amacıyla verileriniz 15 gün süreyle yedek sistemlerde tutulacak ve bu sürenin sonunda kalıcı olarak silinecektir.'),
            _bullet(context, 'Silme işlemi geri alınamaz.'),

            const SizedBox(height: 24),
            _sectionHeader(context, '9. Yaş Sınırı'),
            _body(context,
                'Maarifx, ortaokul ve lise öğrencilerine yönelik bir eğitim hizmetidir. Hizmetimizi kullanmak için minimum 13 yaşında olmanız gerekmektedir.'),
            const SizedBox(height: 8),
            _body(context,
                '13 yaşından küçük bireylerin kişisel verilerini bilerek toplamıyoruz. Eğer 13 yaşından küçük bir kullanıcının verilerini topladığımızı fark edersek, bu verileri derhal silmek için gerekli adımları atacağız.'),

            const SizedBox(height: 24),
            _sectionHeader(context, '10. Hizmet Kapsamı'),
            _body(context,
                'Maarifx hizmeti şu anda yalnızca Türkiye Cumhuriyeti sınırları içinde sunulmaktadır. Hizmetimiz Türkiye Cumhuriyeti yasalarına tabidir ve KVKK hükümleri çerçevesinde yürütülmektedir.'),

            const SizedBox(height: 24),
            _sectionHeader(context, '11. Üçüncü Taraf Hizmetler'),
            _body(context,
                'Hizmetimiz, aşağıdaki üçüncü taraf hizmet sağlayıcılarını kullanmaktadır:'),
            const SizedBox(height: 8),
            _body(context, 'Contabo GmbH', bold: true),
            _bullet(context, 'Amaç: Sanal sunucu (VDS) hizmetleri'),
            _bullet(context,
                'Gizlilik Politikası: contabo.com/en/privacy'),
            const SizedBox(height: 8),
            _body(context,
                'Bu üçüncü taraf hizmetlerin kendi gizlilik politikaları bulunmaktadır ve bu politikaları incelemenizi öneririz.'),

            const SizedBox(height: 24),
            _sectionHeader(context, '12. Gizlilik Politikası Değişiklikleri'),
            _body(context,
                'Bu Gizlilik Politikası\'nı zaman zaman güncelleme hakkımızı saklı tutarız. Yapılacak önemli değişiklikler, web sitemiz ve/veya uygulamamız üzerinden duyurulacaktır.'),
            const SizedBox(height: 8),
            _body(context,
                'Değişikliklerin yürürlüğe girdiği tarihten sonra Hizmetimizi kullanmaya devam etmeniz, güncellenmiş Gizlilik Politikası\'nı kabul ettiğiniz anlamına gelir.'),
            const SizedBox(height: 8),
            _body(context,
                'Önemli değişiklikler için kayıtlı e-posta adresinize bildirim gönderilecektir.'),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: context.textPrimary,
      ),
    );
  }

  Widget _subtitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          color: context.textSecondary,
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: context.textPrimary,
        ),
      ),
    );
  }

  Widget _subsectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: context.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: context.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: context.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
