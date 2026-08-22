# vita3kios

`vita3kios`, Vita3K çekirdeğini iPhone ve iPad'e taşıyan, Apple-native bir
PlayStation Vita emülatörü projesidir.

Proje iki ayrı çalıştırma biçimini hedefler:

- **Direct Game Mode:** Kurulu bir Vita uygulamasını doğrudan başlatır.
- **System Software Mode:** Kullanıcının sağladığı resmî Vita firmware'inden
  gerçek SceShell/LiveArea kullanıcı ortamını çalıştırmayı ve oyunları buradan
  başlatmayı hedefler.

System Software Mode güncel upstream Vita3K'nın hazır bir özelliği değildir.
Firmware kurulumuyla gerçek sistem yazılımını boot etmek farklı işlerdir; bu
özellik ayrı bir çekirdek geliştirme ve doğrulama hattında ele alınacaktır.

## Durum

Proje Faz 1 çıkış doğrulamasındadır. Pinli upstream macOS arm64 Release build,
2/2 CTest ve izole GUI açılış smoke testi geçmiştir; ilk commit'ten temiz
checkout tekrarı M0'ın son kapısıdır. Henüz kurulabilir bir iOS uygulaması yoktur.

Ana plan ve kabul ölçütleri için [ROADMAP.txt](ROADMAP.txt) dosyasına bakın.

## Mimari yön

- SwiftUI tabanlı native iPhone/iPad arayüzü
- Swift ile C++ arasında sürümlü C ABI
- Vita3K core + Dynarmic A32→A64 JIT
- Vulkan → MoltenVK → Metal/CAMetalLayer
- Global, boot-mode ve oyun bazlı ayrıntılı ayar profilleri
- Her iki boot modunda küçük, özelleştirilebilir top-right performans HUD'ı

## İçerik ve firmware

Bu proje Sony firmware'i, oyunları, lisans anahtarlarını veya şifre çözme
verilerini dağıtmaz. Test ve kullanım içeriği kullanıcı tarafından yasal olarak
sağlanmalıdır.

## Lisans

Vita3K GPLv2 kapsamındadır. vita3kios'un birlikte dağıtılan kaynakları ve build
altyapısı GPL ile uyumlu olarak açık tutulacaktır. Faz 1 bağımlılık/lisans
envanteri `LICENSES/DEPENDENCIES.md` altında tutulur; release öncesi tam SBOM ve
hukuki dağıtım kontrolü ayrıca zorunludur.
