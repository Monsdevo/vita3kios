# vita3kios Ayarlar ve Performans HUD Tasarım Sözleşmesi

- Durum: Uygulama öncesi bağlayıcı tasarım tabanı
- Roadmap uyumu: `ROADMAP.txt` v0.2; özellikle Faz 2B, 3, 7, 7A, 8A, 9, 10, 11, 12 ve 15
- Upstream tabanı: Vita3K `496939b602703951277263c7b3e60a9ae36879c1`
- Son güncelleme: 2026-08-22

Bu belge, vita3kios ayar sisteminin ve performans HUD'ının veri modeli, C ABI,
SwiftUI bilgi mimarisi, doğrulama, kalıcılık ve kabul testlerini tanımlar.
`ROADMAP.txt` ana yol haritası olmaya devam eder. Çelişki halinde roadmap
önceliklidir ve bu belge roadmap değişiklik kaydı olmadan kapsam genişletemez.

Bu belgede kullanılan "zorunlu", "olmamalı" ve "yalnızca" ifadeleri uygulama
sözleşmesidir. Öneri olarak işaretlenen ayrıntılar gerçek cihaz ölçümüne göre
değişebilir.

## 1. Değişmez ürün davranışı

- Ayar çözümleme sırası `built-in defaults < global < mode profile < per-title
  override < session override` olacaktır.
- `Direct Game` ve `System Software` ayrı mode profillerine sahip olacaktır.
- System Software içinden bir title açıldığında title override'ı uygulanacak;
  title kapanıp shell'e dönüldüğünde System Software etkili ayarları geri
  yüklenecektir.
- Ayarlar ayrıntılı olacaktır; fakat normal görünüm güvenli seçenekleri,
  `Advanced` görünümü uyumluluk/risk seçeneklerini, `Developer Mode` ise yalnız
  tanılama seçeneklerini gösterecektir.
- Swift katmanı upstream `Config`, C++ nesnesi, YAML veya XML yapısını doğrudan
  görmeyecek ve yazmayacaktır.
- Bir seçenek cihazda veya aktif core sürümünde işlevsel değilse yalnız gri bir
  toggle olarak bırakılmayacak; normal UI'dan gizlenecek veya açık bir
  `Desteklenmiyor` nedeni gösterecektir.
- HUD, Direct Game ve System Software oturumlarında varsayılan olarak açık,
  `Compact` ve sağ üstte olacaktır. Library/ayar ekranında emülasyon oturumu
  yokken gösterilmeyecektir.
- Ölçülmeyen değer sıfırla, tahminle ya da başka bir sayacın vekiliyle
  doldurulmayacaktır. Geçersiz metric gizlenecek veya `—` gösterilecektir.
- Firmware, oyun, lisans anahtarı veya kullanıcıya ait hassas içerik ayar
  profiline, test fixture'ına ya da tanı paketine kopyalanmayacaktır.

## 2. Upstream gerçekliği ve adaptasyon sınırı

Pinlenen upstream sürümde global ayarlar `config.yml` üzerinden `Config`
nesnesine yüklenir. Oyun-bazlı ayarlanabilen alanlar `Config::CurrentConfig`
içinde toplanmıştır. Mevcut custom config yolu
`config/config_<app_path>.xml` biçimindedir.

Upstream custom config davranışının önemli özelliği şudur:

1. Global değerler `CurrentConfig` içine kopyalanır.
2. Custom XML varsa XML'deki tam profil bunun üzerine yüklenir.
3. Custom XML bütün alanların snapshot'ını saklar; alan-bazlı `inherit` durumu
   yoktur.

Bu davranış masaüstü UI için yeterlidir, fakat vita3kios'un mode/title/session
önceliğini tek başına karşılamaz. Örneğin bir title profili oluşturulduktan
sonra global çözünürlük değiştirilirse tam snapshot içindeki eski title değeri
global değişikliği gölgeler. Bu nedenle iOS profil katmanı sparse, yani yalnız
değiştirilmiş alanları saklayacaktır. Bridge, etkili sparse profili
`Config::CurrentConfig` değerlerine dönüştürecektir.

Upstream'in resmî restart-required listesi şu alanları içerir:

- CPU optimizasyonu
- Renderer backend'i
- Grafik aygıtı
- Android custom driver
- High accuracy
- Resolution multiplier
- Memory mapping
- Audio backend
- Validation layer

vita3kios'ta renderer Apple kod yolunda Vulkan'a sabitleneceği için backend,
GPU seçimi ve Android custom driver normal ayar olarak sunulmayacaktır. Diğer
restart alanları descriptor tarafından `sessionRecreateRequired` olarak
işaretlenecektir. Renderer veya audio host güvenle aynı process içinde yeniden
yaratılamazsa capability sonucu bunu `hostRestartRequired` seviyesine
yükseltebilir.

Default değer Swift tarafında ikinci kez hardcode edilmeyecektir. Pinlenen
sürümde bunun neden önemli olduğuna somut bir örnek vardır:
`disable-surface-sync` global macro default'u `true`, çıplak
`CurrentConfig` field initializer'ı ise `false` değeridir; normal load yolunda
global değer `CurrentConfig` içine kopyalanır. UI yalnız bridge'in etkili
default'unu göstermeli, C++ struct initializer'ını tahmin etmemelidir.

### 2.1 Upstream HUD'ın mevcut anlamı

Mevcut Vita3K performans overlay'i şunları sunar:

- `Minimum`: FPS
- `Low`: FPS ve yaklaşık ms/frame
- `Medium`: FPS, ms/frame, average/minimum/maximum
- `Maximum`: Medium verileri ve FPS grafiği

Mevcut FPS, kabul edilen `sceDisplaySetFrameBuf` çağrılarının yaklaşık bir
saniyelik duvar-zamanı aralığında sayılmasıdır. Average/minimum/maximum,
başlangıçta sıfırlardan oluşan 20 adet birer saniyelik FPS bucket'ı üzerinden
hesaplanır. Bu değerler gerçek frametime dağılımı veya 1% low değildir.
vita3kios yeni metrics katmanı hazır olmadan bu alanları farklı anlamla
etiketlemeyecektir.

## 3. Scope ve inheritance modeli

### 3.1 Scope türleri

| Scope | Kalıcılık | Kimlik | Amaç |
| --- | --- | --- | --- |
| Built-in | Salt okunur | Core/schema sürümü | Core'un güvenli başlangıç değerleri |
| Global | Kalıcı | Tek profil | Her oturumun kullanıcı varsayılanı |
| Mode | Kalıcı | `directGame` veya `systemSoftware` | Boot moduna özgü varsayılan |
| Title | Kalıcı | Kanonik title ID | Belirli oyun veya system app uyumluluk ayarı |
| Session | Geçici | Session UUID | Bir sonraki stop'a kadar hızlı/geçici değişiklik |
| Host | Kalıcı, global | Cihaz/app | Native UI, izin, storage ve JIT host tercihleri |

`Title` kimliği mutlak sandbox yolu olmayacaktır. Library scanner'ın doğruladığı
kanonik title ID kullanılacaktır. Aynı title update/reimport edildiğinde profil
korunacaktır. System shell için title ID taklit edilmeyecek; `systemSoftware`
mode profili kullanılacaktır. Gerçek system app title'ları bulunursa kendi
kanonik kimlikleriyle title override alabilir.

### 3.2 Deterministik çözümleme

Her alan `unset` veya tipli bir değer taşır. `unset`, üst katmanın etkili
değerini kullanmak anlamına gelir.

```text
effective = schema.builtInDefaults
effective.apply(profile.global)
effective.apply(profile.mode[session.mode])
if session.activeTitleID != nil:
    effective.apply(profile.title[session.activeTitleID])
effective.apply(session.transientOverrides)
effective = validateAgainstCapabilities(effective)
```

Capability ve güvenlik sınırları kullanıcı override'ından sonra uygulanır;
hiçbir profil fiziksel olarak desteklenmeyen memory mapping yöntemini veya
mevcut olmayan GPU metric'ini zorlayamaz.

System Software oturumundaki geçiş sırası şöyledir:

```text
system shell
  -> built-in + global + systemSoftware + session
system shell launches title
  -> built-in + global + systemSoftware + title + session
title exits to shell
  -> title katmanı kaldırılır; shell etkili ayarları geri yüklenir
```

Title çalışırken değiştirilemeyen bir alan farklılaşıyorsa geçişten önce
session kaynakları yeniden yaratılır veya kullanıcıya tipli hata döner. Eski ve
yeni profil kısmen karıştırılmaz.

### 3.3 Reset ve override davranışı

- `Globali Kullan`, ilgili alanı title/mode profilinden siler; global değeri
  title profiline kopyalamaz.
- `Bu Kategoriyi Sıfırla`, yalnız açık scope'taki kategori anahtarlarını siler.
- `Profili Sıfırla`, açık scope'taki tüm override'ları siler; oyun, save, cache
  veya firmware'e dokunmaz.
- Global reset, anahtarı built-in değere döndürür.
- Session override hiçbir zaman diske yazılmaz. Kullanıcı açıkça `Profile Kaydet`
  işlemi seçerse ayrı bir transaction ile mode/title scope'una dönüştürülür.
- System Software güvenli preset'i salt okunur built-in tabanın parçasıdır.
  Shell doğruluğunu bozabilecek Advanced değişiklikler ayrı onay ister.

## 4. Ayar descriptor modeli

UI hardcode edilmiş toggle listesinden değil, bridge'in döndürdüğü versioned
descriptor'lardan oluşturulacaktır. Her descriptor en az şu bilgileri taşır:

- Yerelleştirilmemiş, sürümler boyunca kararlı `key`
- Yerelleştirme anahtarları: title, kısa açıklama, ayrıntılı uyarı
- Tip: boolean, signed integer, unsigned integer, floating point, string,
  enumeration, bitset veya string list
- Built-in default ve varsa min/max/step/izinli enum değerleri
- İzin verilen scope maskesi
- Görünürlük seviyesi: Standard, Advanced veya Developer
- Capability gereksinimleri ve unsupported nedeni
- Değişim etkisi: live, next boot, session recreate veya host restart
- Risk sınıfı: safe, compatibility, destructive-data veya diagnostic
- Bağımlı alanlar ve cross-field validation kimliği
- Ayarın secret/diagnostic export/redaction davranışı
- Schema'ya eklendiği ve varsa kaldırıldığı sürüm

Swift yerelleştirilmiş başlığı kalıcı anahtar olarak kullanmayacaktır. Enum
değerleri de kullanıcıya görünen metinden değil kararlı koddan oluşacaktır.

### 4.1 Scope kısaltmaları ve uygulama sınıfları

Aşağıdaki tablolarda:

- `G`: Global
- `DG`: Direct Game mode profili
- `SS`: System Software mode profili
- `T`: Title override
- `X`: Geçici session override
- `H`: Host/global native tercih
- `Live`: Güvenle çalışan oturuma uygulanır
- `Boot`: Bir sonraki title/system boot'unda uygulanır
- `Recreate`: Aktif emülasyon session'ı güvenli stop/recreate ister
- `Host`: iOS uygulaması yeniden açılmalıdır
- `Cap`: Capability doğrulanırsa gösterilir
- `Hidden`: Normal iOS UI'da gösterilmez

`Live` işareti yalnız persistence değil, çalışan core üzerinde etkisinin test
edilmiş olmasını gerektirir. Core uygulamıyorsa descriptor geçici olarak `Boot`
veya `Recreate` döndürmelidir.

## 5. Ayar kataloğu ve upstream eşlemesi

Tablodaki `vita3kios key` önerilen kararlı bridge anahtarıdır. Upstream adı `—`
ise ayar iOS host/profile katmanına aittir. Bir upstream anahtarının tabloda
bulunması onun iOS'ta mutlaka görünür olacağı anlamına gelmez.

### 5.1 Core, CPU ve firmware modülleri

| vita3kios key | Upstream anahtarı | Scope | Seviye | Görünürlük | Uygulama | Not |
| --- | --- | --- | --- | --- | --- | --- |
| `core.modules.mode` | `modules-mode` | G,DG,SS,T | Advanced | Firmware module inventory varsa | Boot | Automatic varsayılan; Auto+Manual ve Manual risklidir |
| `core.modules.lle` | `lle-modules` | G,DG,SS,T | Advanced | Kurulu/decrypted module listesi varsa | Boot | Yalnız doğrulanmış `vs0/sys/external` modülleri seçilebilir |
| `cpu.optimizations` | `cpu-opt` | G,DG,SS,T | Advanced | Cap | Recreate | Dynarmic optimizasyonunu kapatmak performansı ciddi düşürebilir |
| `cpu.poolSize` | `cpu-pool-size` | G | Developer | Ölçüm doğrulanana kadar Hidden | Host | Masaüstü varsayılanını iOS'a körlemesine taşımama |
| `jit.status` | — | H | Standard, read-only | Her zaman | — | Enabled/Unavailable/NeedsPreparation/Error; bir performans toggle'ı değildir |
| `jit.launchProvider` | — | H | Advanced | Birden fazla doğrulanmış sağlayıcı varsa | Host | StikDebug/ileride desteklenen yöntem; entitlement üretmez |
| `firmware.activeInstall` | — | H,SS | Standard | Birden fazla firmware snapshot varsa | Boot | Kullanıcının kurduğu doğrulanmış inventory kimliği; PUP yolu saklanmaz |
| `system.mode.safePreset` | — | SS | Standard | Her zaman | Boot | Shell boot için test edilmiş uyumluluk tabanı; per-field override'ları silmez |

### 5.2 GPU, renderer ve görüntü

| vita3kios key | Upstream anahtarı | Scope | Seviye | Görünürlük | Uygulama | Not |
| --- | --- | --- | --- | --- | --- | --- |
| `graphics.backend` | `backend-renderer` | — | — | Hidden; Apple'da Vulkan sabit | Recreate | Değer diagnostic export'a yazılabilir |
| `graphics.device` | `gpu-idx` | — | — | Hidden; tek iOS GPU | Recreate | Birden çok cihaz capability'si oluşursa yeniden değerlendirilir |
| `graphics.customDriver` | `custom-driver-name` | — | — | Hidden; Android-only | Recreate | iOS profil dosyasına yazılmaz |
| `graphics.accuracy` | `high-accuracy` | G,DG,SS,T | Advanced | Vulkan feature sonucuna göre Cap | Recreate | Görsel doğruluk/performance trade-off'u açıklanır |
| `graphics.resolutionScale` | `resolution-multiplier` | G,DG,SS,T,X | Standard | Cihaz limitine göre Cap | Recreate | Upstream UI 0.5x–8x/0.25 adım destekler; iOS seçenekleri ölçümle daraltılabilir; güvenli default 1x |
| `graphics.memoryMapping` | `memory-mapping` | G,DG,SS,T | Advanced | Yalnız runtime mask'taki yöntemler | Recreate | Disabled/Double Buffer/External Host/Page Table; Native Buffer Android-only sayılır |
| `graphics.disableSurfaceSync` | `disable-surface-sync` | G,DG,T,X | Advanced | Memory mapping etkinse Cap | Live | Speed hack; bazı oyunlarda doğruluk için sync gerekir; System Software'de varsayılan gizli/kilitli olabilir |
| `graphics.screenFilter` | `screen-filter` | G,DG,SS,T,X | Standard | `renderer.get_supported_filters` sonucu | Live | Nearest/Bilinear/Bicubic/FXAA/FSR listesini hardcode etme |
| `graphics.vsync` | `v-sync` | — | Advanced | MoltenVK etkisi cihazda kanıtlanana kadar Hidden | Live/Recreate | Upstream masaüstü tooltip'i OpenGL davranışını tarif eder |
| `graphics.framePacing` | — | G,DG,SS,T,X | Standard | Display host capability'sine göre | Live/Recreate | Auto varsayılan; 60/120 Hz davranışı Vita timing'ini hızlandırmamalı |
| `graphics.anisotropicFiltering` | `anisotropic-filtering` | G,DG,SS,T,X | Standard | Max AF capability'sine göre | Live | İzinli değerler 1/2/4/8/16 |
| `graphics.asyncPipelineCompilation` | `async-pipeline-compilation` | G,DG,SS,T,X | Standard | Thread-safe compiler varsa Cap | Live | Stutter azaltabilir; geçici grafik hatası uyarısı |
| `graphics.shaderCache` | `shader-cache` | G,DG,SS,T | Standard | Her zaman | Boot | Cache sürüm/commit uyumu Faz 5 ve 11'e tabidir |
| `graphics.textureCache` | `texture-cache` | G,DG,SS,T | Standard | Her zaman | Boot | RAM/VRAM maliyeti açıklanır |
| `graphics.directSpirv` | `spirv-shader` | — | Developer | Vulkan iOS yolunda anlamı doğrulanana kadar Hidden | Recreate | OpenGL'e özgü davranış iOS'a taşınmaz |
| `graphics.fpsHack` | `fps-hack` | G,DG,T,X | Advanced | Direct title çalışırken | Live | Bazı 30 FPS oyunları 60'a çıkarabilir, oyunu 2x hızlandırabilir; SS'de varsayılan yasak |
| `textures.replacementsEnabled` | `import-textures` | G,DG,T,X | Advanced | Texture klasörü hazırsa | Live | Security-scoped dış yol tutulmaz; app storage'a import edilir |
| `textures.exportEnabled` | `export-textures` | G,DG,T,X | Developer | Yazılabilir alan varsa | Live | Storage kotası ve kullanıcı onayı gerekir |
| `textures.exportFormat` | `export-as-png` | G,DG,T | Developer | Export açıksa | Live | PNG/DDS kararlı enum'una çevrilir |
| `graphics.hashlessTextureCache` | `hashless-texture-cache` | — | Developer | Kullanıldığı kanıtlanana kadar Hidden | Boot | Upstream anahtarın gerçekten tüketildiği sürüm bazında denetlenir |
| `display.scalingMode` | `stretch_the_display_area`, `fullscreen_hd_res_pixel_perfect` | G,DG,SS,T,X | Standard | Her zaman | Live | iOS değerleri Aspect Fit varsayılan, Fill/Crop ve ölçülürse Integer; iki desktop bool'u bridge map eder |
| `display.fileLoadingDelay` | `file-loading-delay` | G,DG,T | Advanced | Her zaman | Boot | 0–30 aralığı; yalnız belirli timing sorunu yaşayan oyunlar |
| `display.shaderCompileNotice` | `show-compile-shaders` | G,DG,SS,T | Standard | Pipeline counter varsa | Live | Native, kısa ve touch engellemeyen bildirim |
| `display.screenshotFormat` | `screenshot-format` | H | Standard | App screenshot özelliği varsa | Live | None/JPEG/PNG; Files export atomik yapılır |

### 5.3 Ses, sistem, kamera ve ağ

| vita3kios key | Upstream anahtarı | Scope | Seviye | Görünürlük | Uygulama | Not |
| --- | --- | --- | --- | --- | --- | --- |
| `audio.backend` | `audio-backend` | — | — | Hidden; iOS native host sabit | Recreate | SDL/Cubeb seçimi sunulmaz |
| `audio.volume` | `audio-volume` | G,DG,SS,T,X | Standard | Her zaman | Live | 0–100 |
| `audio.ngsEnabled` | `ngs-enable` | G,DG,SS,T | Advanced | NGS core derlendiyse Cap | Boot | Uyumluluk etkisi açıklanır |
| `audio.bufferDuration` | — | G,DG,SS,T | Advanced | Audio host destekliyorsa | Recreate | İzinli değerler cihaz ölçümünden gelir; keyfi milisaniye girişi yok |
| `audio.mixWithOthers` | — | H | Standard | AVAudioSession capability'si | Live/Recreate | Route/interruption davranışıyla test edilir |
| `system.pstvMode` | `pstv-mode` | G,DG,SS,T | Advanced | İlgili title/system app için | Boot | Emüle edilen donanım davranışını değiştirir |
| `system.confirmButton` | `sys-button` | G,DG,SS,T | Standard | Her zaman | Boot | Cross/Circle; bazı uygulamalar yok sayabilir |
| `system.language` | `sys-lang` | G,DG,SS,T | Standard | Destekli SCE dil listesi | Boot | UI diliyle karıştırılmaz |
| `system.dateFormat` | `sys-date-format` | G,DG,SS,T | Standard | Her zaman | Boot | YYYY/MM/DD, DD/MM/YYYY, MM/DD/YYYY |
| `system.timeFormat` | `sys-time-format` | G,DG,SS,T | Standard | Her zaman | Boot | 12/24 saat |
| `system.imeLanguages` | `ime-langs` | G,DG,SS,T | Advanced | IME uygulanmışsa Cap | Boot | En az bir dil kalmalı |
| `system.showMode` | `show-mode` | G,SS | Developer | System capability varsa | Boot | Normal oyun ayarı değildir |
| `system.demoMode` | `demo-mode` | G,SS | Developer | System capability varsa | Boot | System Software güvenli preset'inde kapalı |
| `camera.front.source` | `front-camera-type/id/image/color` | G,T | Advanced | İzin + camera capability | Boot | None/Device/Static Image/Solid Color; bookmark yerine app storage |
| `camera.back.source` | `back-camera-type/id/image/color` | G,T | Advanced | İzin + camera capability | Boot | İzin yalnız title gerçekten isterse sorulur |
| `motion.enabled` | ters anlamlı `disable-motion` | G,DG,SS,T,X | Standard | CoreMotion varsa | Live | Bridge negasyonu tek yerde yapar |
| `network.httpEnabled` | `http-enable` | G,DG,SS,T | Advanced | Network core derlendiyse Cap | Boot | Dış ağ davranışı kullanıcıya açıklanır |
| `network.psnPresenceOffline` | `psn-signed-in` | G,DG,SS,T | Advanced | NP emülasyonu varsa | Boot | Gerçek PSN login değildir; açıkça "offline taklit" denir |
| `network.httpTimeoutAttempts` | `http-timeout-attempts` | G,DG,SS,T | Developer | HTTP açıksa | Boot | Range descriptor'dan gelir |
| `network.httpTimeoutSleepMs` | `http-timeout-sleep-ms` | G,DG,SS,T | Developer | HTTP açıksa | Boot | Aşırı değer reddedilir |
| `network.httpReadEndAttempts` | `http-read-end-attempts` | G,DG,SS,T | Developer | HTTP açıksa | Boot | Kararlılık uyarısı |
| `network.httpReadEndSleepMs` | `http-read-end-sleep-ms` | G,DG,SS,T | Developer | HTTP açıksa | Boot | Kararlılık uyarısı |
| `network.adhocAddress` | `adhoc-addr` | G,DG,SS,T | Developer | Uygun interface varsa | Boot | Interface index'i kalıcı kimlik olarak saklanmaz |

### 5.4 Kontroller ve native host ayarları

| vita3kios key | Upstream anahtarı | Scope | Seviye | Görünürlük | Uygulama | Not |
| --- | --- | --- | --- | --- | --- | --- |
| `input.controllerProfile` | `controller-binds`, `controller-axis-binds` | G,DG,SS,T | Standard | GameController varsa | Live | Kararlı Vita action kimlikleri kullanılır; SDL index'i kalıcı kimlik değildir |
| `input.analogMultiplier` | `controller-analog-multiplier` | G,DG,SS,T,X | Advanced | Her zaman | Live | Range capability/schema ile sınırlanır |
| `input.deadzone.left/right` | — | G,DG,SS,T,X | Standard | Analog kontrol varsa | Live | Ayrı stick değerleri ve canlı preview |
| `touch.enabled` | — | G,DG,SS,T,X | Standard | Touch cihazda | Live | Fiziksel controller bağlanınca auto-hide ayrı tercih olabilir |
| `touch.layoutID` | — | G,DG,SS,T | Standard | Her zaman | Live | Portrait/landscape ve sol/sağ el varyantı; koordinatlar normalize saklanır |
| `touch.opacity` | — | G,DG,SS,T,X | Standard | Touch açıkken | Live | Görünür kontrol alt sınırı validation ile korunur |
| `touch.scale` | — | G,DG,SS,T,X | Standard | Touch açıkken | Live | Safe-area dışına taşıyan değer normalize edilmez; editörde hata gösterilir |
| `touch.rearPanelMode` | — | G,DG,SS,T | Advanced | Rear touch kullanan title için | Live | Görünür bölgeler veya öğretilebilir gesture |
| `motion.sensitivity` | — | G,DG,SS,T,X | Advanced | CoreMotion varsa | Live | Orientation dönüşümü host katmanında |
| `haptics.enabled` | — | G,DG,SS,T,X | Standard | Core/Controller haptics varsa | Live | Cihaz ve controller capability'sine göre |
| `lifecycle.pauseOnBackground` | — | H | Standard | Her zaman | Live | Kapatma seçeneği sunulsa bile iOS kaynak kaybında core güvenli pause edebilir |

Upstream fiziksel klavye binding anahtarları iPhone odaklı ilk UI'da
gösterilmeyecektir. iPad keyboard desteği Faz 7/13'te doğrulanırsa ayrı native
action mapping descriptor'ları eklenir; masaüstü key-code dizileri olduğu gibi
taşınmaz.

### 5.5 HUD, log ve developer ayarları

| vita3kios key | Upstream anahtarı | Scope | Seviye | Görünürlük | Uygulama | Not |
| --- | --- | --- | --- | --- | --- | --- |
| `hud.preset` | `performance-overlay`, `performance-overlay-detail` | G,DG,SS,T,X | Standard | Metrics API varsa | Live | Off/Compact/Standard/Detailed; farklı seçim yapılırsa Custom |
| `hud.position` | `performance-overlay-position` | G,DG,SS,T,X | Advanced | Her zaman | Live | Default Top Right; altı pozisyon desteklenebilir |
| `hud.opacity` | — | G,DG,SS,T,X | Advanced | HUD açıksa | Live | Önerilen range 0.35–0.90; erişilebilir minimum kontrast korunur |
| `hud.scale` | — | G,DG,SS,T,X | Advanced | HUD açıksa | Live | Önerilen range 0.75–1.50; Compact default yaklaşık 11 pt |
| `hud.updateRateHz` | — | G,DG,SS,T,X | Advanced | HUD açıksa | Live | Varsayılan 4 Hz; izinli seçenek 1/2/4, 10 Hz yalnız diagnostic |
| `hud.metricSelection` | — | G,DG,SS,T,X | Advanced | Metric capability mask'e göre | Live | Unsupported metric seçimi persist edilse bile çizilmez; UI nedenini gösterir |
| `hud.includeInAppScreenshot` | — | G,DG,SS,T | Advanced | App screenshot compositor destekliyorsa | Live | iOS sistem screen recording için garanti verilmez |
| `logging.level` | `log-level` | G | Developer | Her zaman | Live/Boot | Bridge live logger level desteklemiyorsa Boot |
| `logging.archivePerTitle` | `archive-log` | G,DG,SS,T | Advanced | Log sistemi varsa | Boot | Hassas yol ve lisans verisi redaction'a tabi |
| `logging.compatWarnings` | `log-compat-warn` | G | Developer | Compat DB varsa | Live | Normal kullanıcı uyarılarıyla karıştırılmaz |
| `logging.activeShaders` | `log-active-shaders` | G,DG,SS,T | Developer | Debug build/capability | Boot | Log boyutu uyarısı |
| `logging.uniforms` | `log-uniforms` | G,DG,SS,T | Developer | Debug build/capability | Boot | Yüksek hacim uyarısı |
| `logging.colorSurfaces` | `color-surface-debug` | G,DG,SS,T | Developer | Debug build/capability | Boot | Büyük storage tüketimi uyarısı |
| `debug.validationLayer` | `validation-layer` | G,DG,SS,T | Developer | Validation layer paketliyse | Recreate | Release flavor'da gizlenebilir |
| `debug.gdbStub` | `gdbstub` | G | Developer | Debug build | Host | Port/izin/saldırı yüzeyi nedeniyle release'te kapalı |
| `debug.waitForDebugger` | `wait-for-debugger` | G | Developer | Debug build | Host | Timeout/cancel yolu zorunlu |
| `debug.tracyPrimitive` | `tracy-primitive-impl` | G,DG,SS,T | Developer | Tracy build | Recreate | Çok büyük trace/RAM uyarısı |
| `debug.tracyModules` | `tracy-advanced-profiling-modules` | G,DG,SS,T | Developer | Tracy build | Recreate | Upstream custom XML bu alanları henüz round-trip etmiyor; bridge extension gerekir |

iOS native HUD çizilirken upstream core overlay'i kapalı tutulacaktır; aksi halde
iki overlay aynı anda çizilebilir. Upstream `performance-overlay*` alanları
import sırasında native `hud.*` profiline dönüştürülebilir, fakat yeni UI'nın
tek gerçek kaynağı native profile store olacaktır.

### 5.6 Raw ayar olarak sunulmayacak upstream alanları

Aşağıdaki alanlar unutulmuş değildir; native ürün davranışına dönüştürülecek
veya internal tutulacaktır:

| Upstream anahtarı | iOS davranışı |
| --- | --- |
| `initial-setup`, `show-welcome`, `warn-missing-firmware` | Native onboarding/readiness state'i; kullanıcıya raw toggle olarak gösterilmez |
| `apps-list-grid` | SwiftUI library görünüm tercihi olarak host store'da tutulur |
| `boot-apps-full-screen` | iOS game orientation/session presentation politikasıyla değiştirilir |
| `show-live-area-screen` | Direct Game/System Software mode seçimiyle karıştırılmaz; authentic shell olmayan imitation gerçek OS diye sunulmaz |
| `delay-background`, `delay-start`, `background-alpha` | Masaüstü precompile UI ayarları; native progress tasarımına taşınmaz |
| `pref-path` | Sandbox path resolver yönetir; mutlak container yolu profil ayarı olmaz |
| `discord-rich-presence` | İlk iOS kapsamında yoktur |
| `check-for-updates`, `check-for-updates-mode` | Dağıtım flavor'ına uygun native update davranışı; sideload/Store kararından önce açılmaz |
| `user-id`, `user-auto-connect` | Native user management akışı; ID raw text field olmaz |
| `user-lang` | Native vita3kios UI diliyle değil, upstream Qt UI diliyle ilgilidir; iOS'ta kullanılmaz |
| `current-ime-lang` | IME runtime state'idir; kalıcı kullanıcı ayarı olarak düzenlenmez |
| `controller-led-color` | Controller capability doğrulanırsa native controller profile ayrıntısı olur |
| `keyboard-*` | iPad native action mapping uygulanana kadar gizlidir; masaüstü key code'u doğrudan taşınmaz |
| `turbo-mode`, `custom-driver-name` | Android/Adreno yolu; iOS'ta gizlidir |
| `fullscreen_hd_res_pixel_perfect` | Desktop fullscreen bool'u doğrudan gösterilmez; `display.scalingMode` içine map edilir |

İleride bu alanlardan biri işlev kazanırsa descriptor, capability ve migration
testi eklenmeden UI'ya çıkarılmaz.

## 6. Versioned C ABI

### 6.1 Genel ABI kuralları

- Public header yalnız C99 uyumlu POD tipleri kullanacaktır.
- Her genişletilebilir struct ilk alanlarında `struct_size` ve `abi_version`
  taşıyacaktır.
- C ABI sürümü, settings schema sürümü ve profile-store format sürümü üç ayrı
  sayıdır. Birinin artması diğerlerinin otomatik arttığı anlamına gelmez.
- Enum'ların underlying tipi sabit genişlikli olacaktır.
- Swift ve core arasında heap ownership geçirilmez. Değişken uzunluklu veri için
  caller-owned buffer/two-call size sorgusu veya kopyalayan callback kullanılır.
- String'ler UTF-8'dir; pointer ömrü çağrı sonrasına taşmaz.
- Tüm fonksiyonlar tipli sonuç kodu döndürür; C++ exception ABI dışına çıkmaz.
- Ayar commit'i ve core lifecycle aynı serial emulation queue üzerinde sıralanır.
- UI/render/audio thread'i disk I/O veya schema serialization ile bloklanmaz.

### 6.2 Önerilen tipler

İsimler uygulamada kısaltılabilir; davranış korunmalıdır.

```c
typedef uint64_t v3kios_core_handle_t;
typedef uint64_t v3kios_settings_txn_t;

typedef enum v3kios_setting_scope_v1 {
    V3KIOS_SCOPE_GLOBAL = 1,
    V3KIOS_SCOPE_MODE_DIRECT_GAME = 2,
    V3KIOS_SCOPE_MODE_SYSTEM_SOFTWARE = 3,
    V3KIOS_SCOPE_TITLE = 4,
    V3KIOS_SCOPE_SESSION = 5,
    V3KIOS_SCOPE_HOST = 6
} v3kios_setting_scope_v1;

typedef struct v3kios_setting_descriptor_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t value_type;
    uint32_t scope_mask;
    uint32_t visibility;
    uint32_t apply_requirement;
    uint32_t risk;
    uint64_t capability_mask;
    /* Stable key, localization keys, default/domain and dependency data
       caller-owned output buffers through separate copy functions. */
} v3kios_setting_descriptor_v1;
```

`v3kios_setting_value_v1` tagged union olacaktır. Boolean için integer veya
string kullanmak, enum'u yerelleştirilmiş metin olarak göndermek yasaktır.

### 6.3 Gerekli settings çağrıları

Bridge en az şu işlemleri sağlamalıdır:

```text
settings_get_schema_version
settings_get_descriptor_count
settings_copy_descriptor(index)
settings_copy_enum_choices(key, capabilityContext)
settings_get_override(scope, profileID, key)
settings_get_effective(sessionDescriptor, key)
settings_transaction_begin(scope, profileID)
settings_transaction_set(txn, key, typedValue)
settings_transaction_unset(txn, key)
settings_transaction_validate(txn)
settings_transaction_commit(txn)
settings_transaction_cancel(txn)
settings_reset_category(scope, profileID, category)
settings_reset_profile(scope, profileID)
```

`validate` ve `commit` sonuçları şunları ayırmalıdır:

- Tip/range/domain hataları
- Unsupported capability
- Scope'a izin verilmeyen anahtar
- Cross-field çakışması
- Güvenlik veya compatibility uyarısı
- Canlı uygulanmış anahtarlar
- Next-boot anahtarları
- Session recreate isteyen anahtarlar
- Host restart isteyen anahtarlar
- Disk persistence/recovery sonucu

Commit tamamen atomik olacaktır. Aynı transaction içindeki üç ayardan biri
geçersizse diğer ikisi kalıcılaştırılmaz.

### 6.4 Capability modeli

Capability sonucu yalnız kaba bir bitmask olmamalı; option domain'ini de
daraltabilmelidir. Örnekler:

- Desteklenen screen filter listesi
- Resolution scale alt/üst sınırı ve adımı
- Desteklenen memory mapping yöntemleri
- GPU timestamp query ve timestamp period
- Audio buffer süreleri
- JIT durumu ve hazırlık gereksinimi
- Camera/motion/haptics varlığı
- Metrics alanlarının validity desteği
- Runtime apply veya recreate gereksinimi

Capability cihaz, OS, app flavor, upstream commit ve aktif renderer'a bağlıdır.
Eski capability sonucu yeni session için cache'lenip körlemesine kullanılmaz.

## 7. Validation, migration ve kalıcılık

### 7.1 Validation sırası

Her transaction şu sırayla doğrulanacaktır:

1. Anahtar ve schema sürümü
2. Tip ve UTF-8 doğruluğu
3. Range, step veya enum domain'i
4. Scope izni
5. Runtime capability
6. Cross-field bağımlılıkları
7. System Software güvenli preset politikası
8. Storage/permission gereksinimi
9. Risk uyarısı ve gereken kullanıcı onayı

Örnek zorunlu kontroller:

- AF yalnız 1/2/4/8/16 ve cihaz maksimumunun altında olabilir.
- Resolution scale descriptor adımına oturmalı ve cihaz limitini geçmemelidir.
- LLE module seçimi kurulu firmware inventory'sinde bulunmalıdır.
- Manual module listesi boşsa açık uyarı gerekir.
- Memory mapping yalnız runtime mask'ta bulunan yöntem olabilir.
- Seçilen filter renderer tarafından desteklenmelidir.
- Texture export formatı export kapalıyken etkisiz olarak işaretlenir.
- IME listesi destek aktifse boş bırakılamaz.
- Touch elemanları normalize viewport ve safe area içinde kalmalıdır.
- HUD update rate üst sınırı render-thread callback hızına dönüştürülmemelidir.
- System Software profilinde FPS hack varsayılan olarak reddedilir; yalnız açık
  Advanced onayı ve test capability'siyle uygulanabilir.

Normal kullanıcı değişikliği sessizce clamp edilmez. UI geçerli aralığı gösterir
ve core geçersiz değeri tipli hatayla reddeder. Yalnız migration sırasında artık
desteklenmeyen eski değer güvenli fallback'e alınabilir; bu olay migration
raporuna yazılır.

### 7.2 Profile store

Profile store sparse override'ların kanonik kaynağıdır. Fiziksel encoding için
ayrı ADR yazılabilir; aşağıdaki davranış değişmez:

- `schemaVersion`, oluşturucu app/core sürümü ve son migration sürümü saklanır.
- Built-in default'lar dosyaya kopyalanmaz.
- Global, iki mode profili, title map'i ve host tercihleri birbirinden ayrılır.
- Session override diske girmez.
- Title kimliğinde mutlak app-container yolu bulunmaz.
- Bilinmeyen daha yeni anahtarlar mümkünse kayıpsız korunur.
- Secret, zRIF, pairing file, certificate, firmware/game yolu ve security-scoped
  bookmark bu store'a konmaz.

Upstream `config.yml` ve `config_<app_path>.xml` için bridge adapter'ı bulunur.
İlk import sırasında tanınan global/custom alanlar sparse modele dönüştürülür.
Upstream formatı değiştirilirse migration test edilmeden yeni pin kabul edilmez.
Bridge'in ürettiği runtime `Config` bir türetilmiş değer sayılır; Swift'in ikinci
bir config gerçeği oluşturmasına izin verilmez.

### 7.3 Atomik yazım ve kurtarma

Kalıcılık tek writer queue üzerinden yürür:

1. Yeni içerik aynı dizinde benzersiz temp dosyaya yazılır.
2. Dosya flush/fsync edilir.
3. Temp dosya yeniden parse edilerek schema doğrulanır.
4. Mevcut son-geçerli sürüm `.bak` olarak korunur.
5. Temp dosya atomik rename ile asıl dosyanın yerine geçer.
6. Desteklenen platformda parent directory fsync edilir.
7. Commit sonucu ancak bundan sonra başarı döner.

Açılışta asıl dosya bozuksa `.bak` denenir. Backup da bozuksa built-in/global
güvenli değerlerle boot devam eder, bozuk dosyalar tanı için yeniden adlandırılır
ve kullanıcıya non-blocking uyarı gösterilir. Bozuk config oyun veya system
shell boot'unu sonsuz crash döngüsüne sokmamalıdır.

### 7.4 Migration ilkeleri

- Migration `N -> N+1` küçük, tekrar çalıştırılabilir adımlardan oluşur.
- Her adım eski fixture, beklenen yeni çıktı ve downgrade davranışıyla test edilir.
- Rename edilen anahtarın eski adı yalnız migration'da kabul edilir; UI iki
  anahtarı aynı anda yazmaz.
- Kaldırılan capability değeri override store'da audit için korunabilir, fakat
  effective profile güvenli fallback kullanır ve UI `Artık desteklenmiyor` der.
- Upstream pin değişiminde config diff envanteri Faz 15 sync checklist'ine girer.
- Migration log'u değerleri değil anahtar ve sonuç kodlarını içermelidir; hassas
  kullanıcı verisi loglanmaz.

## 8. SwiftUI bilgi mimarisi

### 8.1 Giriş noktaları

- Ana Settings ekranı global/host ayarlarına açılır.
- Library game detail içindeki `Settings`, doğrudan ilgili title scope'una açılır.
- System Software readiness/boot ekranındaki `Settings`, `systemSoftware` mode
  profiline açılır.
- Pause overlay içindeki `Settings`, aktif profile ve yalnız güvenli live ayarlara
  hızlı erişim verir. Recreate isteyen değişiklik yapılırsa `Şimdi yeniden başlat`
  veya `Sonraki açılışta uygula` sonucu gösterilir.

### 8.2 Navigasyon

iPhone `NavigationStack`, iPad `NavigationSplitView` kullanır. Settings ana
ekranı şu sırada görünür:

1. Aktif scope/profile başlığı
2. Arama
3. `Basic / Advanced` görünüm seçimi
4. Readiness özetleri: firmware, JIT, renderer/audio capability
5. Kategoriler
6. Yalnız değiştirilmiş ayarları gösterme
7. Profil reset/export işlemleri
8. Developer Mode etkinse Developer/Logging

Kategori sırası roadmap ile aynıdır:

- System/Firmware
- Core/CPU/JIT
- GPU/Renderer
- Display/Frame Pacing
- Audio
- Input/Controller
- Touch
- Motion
- Camera/Microphone
- Network
- Storage/Cache
- Compatibility
- Performance HUD
- Developer/Logging

### 8.3 Ayar satırı

Her satır en az şunları gösterir:

- Yerelleştirilmiş başlık
- Etkili değer
- Değer kaynağı: Built-in, Global, Direct Game, System Software, Title veya Session
- `Override` durumu ve `Globali/Üst Profili Kullan` işlemi
- Kısa açıklama
- Gerekirse `Advanced`, `Compatibility`, `Developer`, `Restart` rozeti
- Unsupported ise kısa neden ve ayrıntı ekranı

Slider, keyfi hassasiyete sahipmiş gibi gösterilmeyecek; descriptor adımıyla
snap edecektir. Uzun enum veya module listesi ayrı seçim sayfası açacaktır.
Riskli toggle açılmadan önce sonucu anlatan tek onay gösterilir. Aynı değeri
kapatmak için tekrar onay istenmez.

### 8.4 Basic, Advanced ve Developer

- Basic görünüm performans/kalite, ses, kontrol, sistem dili ve HUD gibi güvenli
  günlük ayarları içerir.
- Advanced görünüm module policy, memory mapping, accuracy, surface sync, FPS
  hack, texture replacement ve network timing gibi uyumluluk seçeneklerini açar.
- Developer Mode ayrı ve kalıcı bir host tercihidir. İlk açılışta log boyutu,
  performans ve kararlılık etkisi açıklanır. Release flavor capability sunmuyorsa
  ilgili developer satırları hiç oluşturulmaz.
- Arama görünürlük sınırını aşmaz; Developer Mode kapalıyken gizli developer
  anahtarını sonuçlarda sızdırmaz.

### 8.5 Erişilebilirlik ve yerelleştirme

- Kullanıcı metinleri descriptor localization key'lerinden Türkçe ve İngilizce
  tablolara çözülür; stable key gösterilmez.
- Dynamic Type satırları kırpmamalı; value/detail alt satıra geçebilmelidir.
- VoiceOver başlık, etkili değer, kaynak, risk ve apply gereksinimini tek anlamlı
  label/hint olarak okumalıdır.
- Sadece renkle override veya risk anlatılmamalıdır.
- Controller/keyboard focus sırası kategori düzeniyle aynı olmalıdır.
- Reduce Motion, scope değişim animasyonlarını ve HUD graph animasyonunu azaltır.

## 9. Metrics veri sözleşmesi

### 9.1 Snapshot yapısı

Core, preallocated/double-buffered bir snapshot yayınlayacaktır. SwiftUI render
veya emulation thread'inden callback almayacak; kendi 2–4 Hz zamanlayıcısında son
snapshot'ı kopyalayacaktır.

```c
typedef struct v3kios_metrics_snapshot_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t monotonic_timestamp_ns;
    uint64_t session_id;
    uint64_t sample_epoch;
    uint64_t validity_mask;
    uint32_t session_kind;
    uint32_t run_state;

    double guest_fps;
    double present_fps;
    double guest_frame_interval_ema_ms;
    double guest_frame_interval_p50_ms;
    double guest_frame_interval_p95_ms;
    double one_percent_low_fps;
    double cpu_frame_time_ms;
    double gpu_frame_time_ms;

    uint64_t resident_memory_bytes;
    uint64_t jit_cache_bytes;
    uint64_t jit_compiled_blocks;
    uint64_t pipeline_compiles_total;
    uint64_t audio_underruns_total;
    uint32_t thermal_state;
    uint32_t guest_width;
    uint32_t guest_height;
    double resolution_scale;
} v3kios_metrics_snapshot_v1;
```

Alan isimleri ilk ABI uygulanırken değişebilir; `struct_size`, version, validity,
session, monotonic timestamp ve aşağıdaki semantik tanımlar değişmemelidir.
Her session boot/restart ve shell/title geçişinde `sample_epoch` artar. UI farklı
epoch örneklerini aynı rolling grafik içinde birleştirmez.

### 9.2 Gerçek ölçüm tanımları

| Metric | Bağlayıcı tanım | İlk kaynak | Geçerlilik koşulu |
| --- | --- | --- | --- |
| Guest FPS | Kabul edilmiş guest `sceDisplaySetFrameBuf` olay sayısı / pause hariç monotonic elapsed time | SceDisplay hook | En az iki frame ve pozitif pencere |
| Present FPS | Başarılı host present submission/completion sayısı / monotonic elapsed time | Vulkan/MoltenVK present sınırı | Present hook doğrulanmış olmalı |
| Guest frame interval | Ardışık guest-frame timestamp farkı; Compact için EMA, Detailed için dağılım | Preallocated timestamp ring | Pause/epoch sınırı karıştırılmaz |
| Rolling average FPS | Son 10 s veya descriptor'daki pencere boyunca toplam guest frame / gerçek elapsed | Timestamp ring | Yeterli zaman örneği |
| 1% low FPS | Aynı rolling penceredeki frame interval'ların 99. yüzdeliğinin tersi `1000 / p99_ms` | Timestamp ring | En az 10 s ve yeterli frame; aksi halde invalid |
| CPU frame time | Açıkça tanımlanan emulation/render-preparation critical path'in ölçülen wall süresi | Core instrumentation | Başlangıç/bitiş noktaları aynı sürümde doğrulanmış |
| GPU frame time | Vulkan timestamp query ile emüle render workload başlangıç/bitiş farkı | Vulkan query pool | Queue timestamp desteği ve geçerli query sonucu |
| Resident memory | Uygulama process'inin desteklenen public iOS mekanizmasıyla ölçülen physical footprint/RSS | PlatformIOS | API destekli ve okuma başarılı |
| Thermal state | iOS `ProcessInfo` nominal/fair/serious/critical durumu | PlatformIOS | Her zaman veya host capability |
| Audio underrun | Output callback'in istediği frame sayısını PCM ring buffer sağlayamadığında monotonic sayaç artışı | iOS audio host | Audio session aktif |
| Pipeline compile | Başarıyla tamamlanan pipeline/shader compilation için monotonic total ve sample delta | Vulkan renderer | Counter reset yerine monotonic tutulmalı |
| JIT cache/blocks | Dynarmic'in doğrudan raporladığı byte/block sayısı | Dynarmic adapter | Core gerçek API sağlıyorsa |
| Resolution | Guest framebuffer boyutu, resolution multiplier ve host drawable ayrı alanlar | Display/renderer | Frame/surface hazır |
| Emulation speed | Guest virtual time ilerlemesi / pause hariç wall time, açık nominal hedefle | Gelecek timing instrumentation | Vblank thread sayımı tek başına yeterli değildir |

`ms/frame = 1000/FPS` yalnız FPS'in cebirsel tersidir; CPU veya GPU süresi diye
etiketlenmez. Compact `frame ms`, timestamp ring'den gelen guest frame interval
EMA'sıdır.

### 9.3 Unsupported metrics ilkesi

- GPU utilization, GPU timestamp süresinden türetilmez. Gerçek utilization API'si
  yoksa alan invalid kalır.
- CPU utilization, CPU frame time'dan türetilmez. Gerçek process/thread CPU
  sampler'ı doğrulanmadan yüzde gösterilmez.
- Emulation speed, 60 Hz çalışan bağımsız vblank thread'inin tick oranıyla
  tahmin edilmez.
- JIT aktifliği executable memory ayrılabildi varsayımıyla gösterilmez; JIT
  adapter'ın doğrulanmış çalışma durumu gerekir.
- Thermal state numeric sıcaklığa çevrilmez; iOS'un semantik state'i gösterilir.
- Bir metric runtime'da geçersizleşirse son değer sonsuza kadar tutulmaz.
  Validity kaldırılır ve UI alanı `—` yapar veya gizler.
- Detailed/Custom preset bir unsupported metric isterse UI nedenini gösterir;
  `0`, `N/A 0%` veya sahte normal değer çizmez.

### 9.4 Threading ve örnekleme

- Frame, present ve audio event hook'ları yalnız atomik sayaç/timestamp ring'e
  yazar; formatlama, sorting, disk veya Swift callback yapmaz.
- Ring buffer önceden ayrılır. Emülasyon sırasında per-frame heap allocation
  yapılmaz.
- Aggregator varsayılan 4 Hz snapshot üretir. Detailed ağır metric'ler 2 Hz
  alt-publisher kullanabilir.
- UI snapshot'ı MainActor'a küçük POD kopyası olarak taşır.
- Monotonic clock kullanılır. Saat dilimi/sistem saati değişimi metric'i bozmaz.
- Pause, background, stop ve epoch geçişinde zaman penceresi kapatılır. Resume'da
  önceki pause süresi frame interval'a eklenmez.
- İlk guest frame gelmeden FPS sıfır değil invalid'dir. İlk geçerli HUD verisi
  ilk frame'den sonra en geç bir saniye içinde yayınlanır.

## 10. HUD görsel ve etkileşim sözleşmesi

### 10.1 Presetler

| Preset | İçerik | Yerleşim |
| --- | --- | --- |
| Off | HUD çizilmez; metrics toplama yalnız başka consumer yoksa minimuma iner | — |
| Compact | Guest FPS ve guest frame interval EMA | Tek satır: `59.9 FPS · 16.7 ms` |
| Standard | Guest/present FPS, rolling average ve 1% low | En fazla iki kısa satır |
| Detailed | Standard + geçerli CPU/GPU time, memory, thermal, audio, pipeline, JIT, resolution ve pacing graph | Küçük panel; kullanıcı açtığında |
| Custom | Kullanıcının capability içinden seçtiği metric sırası | Seçime göre; Compact sınırı aşılırsa panel |

Varsayılan tüm yeni kurulumlarda:

```text
preset = Compact
position = Top Right
updateRate = 4 Hz
scale = 1.0
```

Upstream overlay varsayılanı off/top-left olsa bile vita3kios ürün varsayılanı
roadmap gereği on/top-right'tır.

### 10.2 SwiftUI yerleşimi

HUD render surface'in native container'ında şu kavramsal düzeni kullanır:

```text
ZStack(alignment: .topTrailing)
  RenderSurface (gerekirse ekran kenarlarına kadar)
  PerformanceHUD
    safeArea.top + 8 pt
    safeArea.trailing + 8 pt
```

- HUD, `CAMetalLayer` görüntüsünün üzerinde SwiftUI/native host katmanında
  çizilir; Vita framebuffer'a yakılmaz.
- Landscape orientation, Dynamic Island/notch ve iPad multitasking safe area
  her layout pass'te hesaba katılır.
- Compact başlangıç fontu yaklaşık 11 pt ve `monospacedDigit` olacaktır.
- Yatay/dikey padding yaklaşık 6/4 pt, arka plan yüksek kontrastlı yarı saydam
  material/capsule olacaktır. Opacity ayarı metni okunamaz hale getiremez.
- HUD `allowsHitTesting(false)` olacaktır; touch overlay veya oyun gesture'ını
  yakalamaz.
- Canlı değişen değerler VoiceOver ile saniyede birkaç kez anons edilmez.
  HUD varsayılan olarak accessibility live region değildir; Pause/Settings
  ekranında son metric'lerin erişilebilir metin özeti sunulur.
- Reduce Motion açıkken graph geçiş/animasyonu kapatılır veya azaltılır.
- `Paused` durumunda rolling pencereler donar/sıfırlanır ve küçük `Paused`
  durumu gösterilebilir; eski FPS çalışıyormuş gibi güncellenmez.
- Boot/title geçişinde eski epoch verisi yeni title'ın HUD'ında gösterilmez.

### 10.3 Screenshot ve kayıt

Uygulama içi screenshot pipeline'ı HUD'ı ayrı compositor pass olarak dahil veya
hariç tutabiliyorsa kullanıcı seçimi sunulur. Bu kabiliyet yoksa seçenek gizlenir.
iOS sistem screen recording'in SwiftUI overlay'i yakalayıp yakalamamasını app'in
tam kontrol ettiği iddia edilmeyecektir.

## 11. Test matrisi ve kabul kriterleri

### 11.1 Settings unit ve integration testleri

- Her descriptor stable key bakımından benzersizdir.
- Her exposed upstream alanı tip, default, scope ve apply requirement ile round-trip
  edilir.
- Property-based merge testleri her anahtar için built-in/global/mode/title/session
  kombinasyonunu ve `unset` davranışını doğrular.
- Direct Game, System Software, shell->title->shell geçişleri aynı fixture setiyle
  test edilir.
- Title profili create/edit/remove ve game update/reimport sonrasında korunur.
- Unsupported filter/memory mapping/range değeri typed error verir; UI gizleme
  ile core validation aynı capability snapshot'ını kullanır.
- Live ayar çalışan session'ı değiştirir; Boot/Recreate alanı yarım uygulanmaz.
- Bir transaction içindeki tek invalid alan bütün commit'i geri alır.
- Temp write, fsync öncesi crash, rename öncesi crash ve bozuk primary dosya
  senaryoları last-known-good recovery'yi doğrular.
- Her migration için old fixture -> new canonical store snapshot testi vardır.
- Bilinmeyen yeni anahtar kayıpsız korunur veya açık incompatibility hatası verir.
- Config/log export zRIF, bookmark, kişisel yol, pairing veya certificate içermez.
- Thread Sanitizer destekli host testinde settings read/commit ile session lifecycle
  arasında data race bulunmaz.

### 11.2 Settings UI testleri

- iPhone NavigationStack ve iPad NavigationSplitView'da tüm kategoriler erişilir.
- Game detail title scope'una, System Software ekranı doğru mode scope'una açılır.
- Effective value ve kaynak rozeti gerçek merge sonucuyla aynıdır.
- `Globali Kullan`, override'ı siler; değeri kopyalamaz.
- Basic görünüm Advanced/Developer anahtarlarını sızdırmaz; arama bu sınırı aşmaz.
- Unsupported option yanlışlıkla etkinleştirilemez.
- Restart/recreate değişikliği kullanıcıya uygulanma zamanını doğru söyler.
- Dynamic Type, VoiceOver, yüksek kontrast, Reduce Motion ve yalnız controller/
  keyboard navigasyonu kritik akışlarda geçer.
- Türkçe/İngilizce string'lerde stable key veya hardcode edilmiş geliştirici metni
  görünmez.

### 11.3 Metrics doğruluk testleri

Deterministik fake monotonic clock ve sentetik event dizileriyle:

- Guest/present frame sayıları ve FPS hesabı tam eşleşir.
- 30, 60 ve düzensiz frame dizilerinde EMA, p50, p95 ve p99/1% low beklenen
  toleranstadır.
- Pause/background süresi interval'a katılmaz.
- Stop/restart ve shell/title epoch'ları birbirine karışmaz.
- Ring wrap, tek frame, sıfır elapsed, uzun stall ve timestamp geri gitme guard'ı
  test edilir.
- Audio underrun yalnız gerçekten eksik PCM frame olduğunda artar.
- Unsupported GPU/JIT/CPU metric validity biti kapalı kalır ve sıfır diye sunulmaz.

Gerçek cihaz karşılaştırmasında:

- Guest frame count, 10 saniyelik trace içindeki kabul edilmiş SceDisplay olay
  sayısıyla birebir olmalıdır.
- Present count, Vulkan/MoltenVK capture veya instrumented present hook ile
  birebir olmalıdır.
- FPS sapması uzun pencerede en fazla 1 FPS veya %2'den büyük olan toleranstır.
- Frame interval ortalama/percentile sapması referans trace'e karşı en fazla
  0.5 ms veya %5'ten büyük olan toleranstır.
- GPU time yalnız Vulkan timestamp sonucu Metal System Trace ile makul biçimde
  korele oluyorsa geçerli capability sayılır.
- Memory ve thermal alanları aynı anda alınan host reference değer/durumuyla
  eşleşmelidir.

### 11.4 HUD görsel ve davranış testleri

- Compact HUD Direct Game ve System Software'de ilk geçerli frameden sonra en
  geç bir saniyede görünür.
- Default top-right yerleşim tüm desteklenen iPhone/iPad orientation ve safe-area
  fixture'larında notch, Dynamic Island, status/home indicator ve multitasking
  sınırlarına girmez.
- Compact tek satır mümkün değilse kontrollü iki satıra kırılır; ekran dışına
  taşmaz ve oyun kontrolünü kapatmaz.
- `allowsHitTesting(false)` UI testinde HUD altındaki touch/virtual button aynı
  koordinatta çalışır.
- Off/Compact/Standard/Detailed/Custom ve runtime metric validity değişimi snapshot
  testleriyle doğrulanır.
- Pause/resume/background/foreground/rotation/surface recreation sırasında stale
  değer, crash veya layout sıçraması olmaz.
- VoiceOver canlı sayıları tekrar tekrar anons etmez; Pause ekranındaki özet
  erişilebilir olur.

### 11.5 Performans kabul kriterleri

MHUD kapısı için aynı cihaz, aynı build, aynı içerik/checkpoint ve sabit ayarlarla
HUD Off/Compact A/B testi en az üç 10 dakikalık koşu olarak yapılır. İlk shader
warm-up ayrı tutulur.

Kabul kriterleri:

- Compact HUD'ın ek CPU yükü roadmap ile uyumlu olarak `<= %1` olmalıdır.
- p95 frame-time farkı ölçüm gürültüsü içinde kalmalı; başlangıç mühendislik
  sınırı `<= 0.2 ms` veya Off koşularının %95 güven aralığıdır, hangisi daha
  genişse o kullanılır.
- Event hook'larında steady-state per-frame heap allocation olmamalıdır.
- Metrics ring/snapshot belleği sabit ve cihazdan bağımsız üst sınırlı olmalıdır;
  büyüyen sınırsız history tutulmaz.
- HUD kapalı ve başka consumer yokken ağır CPU/GPU query'leri çalıştırılmaz.
- Detailed metric capability'si GPU stall/readback oluşturuyorsa o metric release
  build'de unsupported işaretlenir.
- 2 saatlik Direct Game ve System Software soak testinde metric counter overflow,
  memory growth, deadlock veya UI update backlog görülmemelidir.

MHUD yalnız görsel olarak sayaç görünmesiyle tamamlanmış sayılmaz. İki boot
modunda semantik doğruluk, validity davranışı, safe-area yerleşimi ve performans
bütçesi birlikte geçmelidir.

## 12. Uygulama sırası

Bu belge roadmap faz sırasını değiştirmez. İlgili işler şu sırada uygulanır:

1. Faz 2B'de descriptor/value/result tipleri, capability ve settings/metrics ABI
   iskeleti oluşturulur.
2. Faz 2C'de System Software boot target ve mode profile kimliği doğrulanır.
3. Faz 3–5'te iOS device capability domain'leri gerçek renderer/audio/JIT
   sonuçlarıyla doldurulur.
4. Faz 7'de ProfileStore, merge motoru ve SwiftUI settings ekranları oluşturulur.
5. Faz 7A'da timestamp ring, metric publisher ve native HUD uygulanır.
6. Faz 8/8A/9'da session, system shell, audio/input lifecycle metric ve setting
   uygulaması tamamlanır.
7. Faz 10–12'de persistence, migration, end-to-end, fuzz/recovery ve privacy
   testleri kapatılır.
8. Faz 15'te her upstream pin değişiminde config/HUD kaynak diff'i ve migration
   matrisi yeniden çalıştırılır.

## 13. Pinlenmiş upstream kaynakları

- [Global Config anahtarları ve HUD enum'ları](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/config/include/config/config.h)
- [Per-app `CurrentConfig`](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/config/include/config/state.h)
- [Custom config load/save ve restart-required listesi](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/config/src/settings.cpp)
- [Settings commit ve runtime apply davranışı](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/app/src/app_init.cpp)
- [Mevcut runtime FPS hesabı](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/app/src/app.cpp)
- [`sceDisplaySetFrameBuf` frame sayacı](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/modules/SceDisplay/SceDisplay.cpp)
- [Mevcut performance overlay preset ve çizimi](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/overlay/src/perf_overlay.cpp)
- [Apple renderer seçiminin Vulkan'a sabitlenmesi ve runtime settings](https://github.com/Vita3K/Vita3K/blob/496939b602703951277263c7b3e60a9ae36879c1/vita3k/app/src/app_init.cpp)

Bu kaynakların davranışı yeni upstream pin'de değişirse tablo sessizce geçersiz
bırakılmaz; Faz 15 kapsamında belge, schema ve migration testleri birlikte
güncellenir.
