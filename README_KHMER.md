# ការណែនាំលម្អិត៖ ការដំឡើង និង Compile Mod RosCambo (Rules of Survival) លើ VPS

ឯកសារនេះត្រូវបានបង្កើតឡើងសម្រាប់ពន្យល់លម្អិតជាភាសាខ្មែរ អំពីរបៀបយក Folder `RosCamboMod` ទៅកាន់ VPS (Linux/macOS) ដើម្បី Compile ចេញជា `.dylib` និង Inject ចូលទៅក្នុង IPA របស់ RosCambo។

---

### ១. លក្ខណៈពិសេសទាំងអស់ (Feature List)

#### ក. ប្រព័ន្ធ ESP (Visuals)
* **ESP Box:** អាចជ្រើសរើសបាន ៣ ប្រភេទ (2D Rectangle, 3D Corner Box, និង Filled Box)។
* **Snaplines:** បន្ទាត់ចង្អុលទៅកាន់សត្រូវ (អាចកំណត់ចេញពី បាតអេក្រង់, កណ្តាល Crosshair, ឬ កំពូលអេក្រង់)។
* **Skeleton / Bone ESP:** គូរគ្រោងឆ្អឹងពេញលេញរបស់សត្រូវ (ក្បាល, ក, ទ្រូង, ត្រគាក, ដៃឆ្វេង/ស្តាំ, ជើងឆ្វេង/ស្តាំ)។
* **Health Bar:** បន្ទាត់ឈាមផ្លាស់ប្តូរពណ៌តាមកម្រិតឈាម (បៃតង -> លឿង -> ក្រហម) និងបង្ហាញលេខឈាម។
* **Distance & Name:** បង្ហាញចម្ងាយជាម៉ែត្រ (m) និងឈ្មោះសត្រូវ ឬសម្គាល់ [BOT]។
* **360 Offscreen Indicator:** រ៉ាដាព្រួញជុំវិញអេក្រង់ សម្រាប់ប្រាប់ទីតាំងសត្រូវដែលនៅក្រៅ FOV ឬនៅពីក្រោយខ្នង (មានប្រយោជន៍បំផុតលើ Ghillie Map)។

#### ខ. ប្រព័ន្ធ Aimbot (Targeting)
* **Master Toggle:** បើក/បិទ Aimbot ភ្លាមៗ។
* **Target Bone Selection:** អាចជ្រើសរើសទីតាំងតម្រង់ (Head, Neck, Chest, Pelvis)។
* **Speed Presets:**
  * **Aim 100% (Instant Rage):** ចាក់សោរក្បាលសត្រូវភ្លាមៗ (Instant Snap)។
  * **Aim 50% (Legit Assist):** ទាញពាក់កណ្តាលចម្ងាយក្នុងមួយ Frame ធ្វើឱ្យការបាញ់រលូនដូចមនុស្សលេងធម្មតា។
  * **Custom Smooth:** អាចកំណត់កម្រិត Smooth តាមចិត្ត (1.0 ដល់ 30.0)។
* **Aim 360:** បាញ់បានជុំវិញខ្លួន 360 ដឺក្រេ ដោយមិនខ្វល់ពី FOV។
* **Silent Aim:** បាញ់ត្រូវក្បាលសត្រូវដោយមិនចាំបាច់ងាកកាមេរ៉ា (Bullet Direction Intercept)។
* **FOV Circle:** រង្វង់កំណត់តំបន់ Aimbot លើអេក្រង់។

---

### ២. ការដំណើរការលើផែនទី Ghillie Island (Ranked Match)

នៅលើផែនទី Ghillie Island (Ranked Match) របស់ Rules of Survival:
1. **NeoX SpaceData:** ហ្គេមប្រើប្រព័ន្ធ Cell Streaming និង SpaceData។ កូដរបស់យើងបានភ្ជាប់ជាមួយ `EntityManager` ដើម្បី Update បញ្ជីសត្រូវតាមរយៈ Area of Interest (AoI រង្វង់ 500 ម៉ែត្រ)។
2. **Terrain Z-Filter:** ដីនៅលើកោះ Ghillie មានភ្នំ និងជម្រាលខ្ពស់ទាបច្រើន។ ប្រព័ន្ធ WorldToScreen ប្រើ ViewProjection Matrix 4x4 របស់ Camera ផ្ទាល់ ធ្វើឱ្យប្រអប់ ESP និង Skeleton នៅជាប់ខ្លួនសត្រូវជានិច្ច ទោះបីជាសត្រូវកំពុងរត់លើភ្នំ ឬចុះចំណោតក៏ដោយ។
3. **Stance Detection:** ស្គាល់សភាពសត្រូវ (ឈរ, អង្គុយ, ដេកវារ ឬកំពុងលោតឆ័ត្រយោង) ដើម្បីគូរក្បាល និងប្រអប់ឱ្យត្រូវទីតាំងជានិច្ច។

---

### ៣. របៀប Compile លើ VPS មួយជំហានម្តងៗ

#### ជំហានទី ១៖ Copy Folder ទៅកាន់ VPS
ប្រើប្រាស់ SCP ឬ SFTP ដើម្បីផ្ញើ folder ពីកុំព្យូទ័រទៅ VPS៖
```bash
scp -r d:/RosCambo/RosCamboMod user@vps_ip:/home/user/
```

#### ជំហានទី ២៖ ចូលទៅកាន់ VPS និងផ្តល់សិទ្ធិ Run Script
```bash
cd /home/user/RosCamboMod
chmod +x build.sh inject.sh
```

#### ជំហានទី ៣៖ Compile កូដចេញជា `roscheat.dylib`
គ្រាន់តែដំណើរការ script `build.sh` (Script នេះនឹង auto-download ImGui Metal backend និង compile តាម Makefile)៖
```bash
./build.sh
```
នៅពេលជោគជ័យ អ្នកនឹងទទួលបាន file: `roscheat.dylib` (arm64)។

#### ជំហានទី ៤៖ Inject ចូលទៅក្នុង RosCambo IPA
ចម្លង file `RoS-Cambo-iOS-v6-fullscreen.ipa` ដាក់ក្នុង folder ជាមួយគ្នា រួចដំណើរការ៖
```bash
./inject.sh RoS-Cambo-iOS-v6-fullscreen.ipa RoS-Cambo-Modded.ipa
```
Script នេះនឹង៖
1. ដកស្រង់ IPA (Unzip Payload)
2. បញ្ចូល `roscheat.dylib` ទៅក្នុង App
3. ប្រើ `optool` បញ្ចូល `LC_LOAD_DYLIB` ទៅក្នុង `client` executable
4. Sign កូដដោយប្រើ `ldid -S`
5. វេចខ្ចប់ជា file `RoS-Cambo-Modded.ipa` រួចជាស្រេច!

---

### ៤. ការដំឡើងលេងលើទូរស័ព្ទ iPhone / iPad
* យក file `RoS-Cambo-Modded.ipa` ទៅដំឡើងតាមរយៈ **TrollStore** (ល្អបំផុត មិនបាច់ Sign ៧ ថ្ងៃ) ឬប្រើ **Sideloadly / AltStore / Esign** ជាមួយ Apple ID របស់អ្នក។
* នៅពេលបើកហ្គេម នឹងមានប៊ូតុងអណ្តែត `ROSCAMBO` នៅជ្រុងខាងលើអេក្រង់។ ចុចលើវាដើម្បីបើក/បិទ Menu ImGui!
