# Vehicle Spawner GUI (StarterGui)

Redesign UI menu spawn kendaraan untuk Roblox. **Isinya hanya GUI, tanpa sistem/script spawn.**

![Preview desktop](docs/preview-desktop.png)

<details>
<summary>Preview di HP (844 × 390)</summary>

![Preview HP](docs/preview-phone.png)
</details>

> Gambar di atas adalah render preview. Di Roblox, motor 🏍️ merah itu hanya placeholder sampai kamu memasang gambar kendaraan sendiri.

## Cara pasang

**Opsi A: file model (paling gampang)**
1. Download `StarterGui/VehicleSpawnerGui.rbxmx`
2. Di Roblox Studio: klik kanan **StarterGui** → **Insert from File...** → pilih file tersebut

**Opsi B: Command Bar**
1. Studio → **View** → **Command Bar**
2. Copy seluruh isi `src/VehicleSpawnerGui.luau`, paste ke Command Bar, tekan **Enter**
3. `VehicleSpawnerGui` otomatis dibuat di StarterGui (versi lama dengan nama sama akan diganti)

## Isi GUI

```
VehicleSpawnerGui (ScreenGui)
├── OpenButton                 tombol HUD "GARAGE" di kiri layar
├── Backdrop                   layer gelap di belakang menu
└── Main
    ├── Header
    │   ├── Title              "Welcome, <nama>" (RichText)
    │   ├── InsertButton
    │   └── CloseButton
    ├── Browser
    │   ├── Search.SearchBox   TextBox
    │   ├── SortButton
    │   ├── Tabs               Tab_All / Tab_Motorcycle / Tab_Car / Tab_Gamepass
    │   ├── ResultCount
    │   └── Grid               ScrollingFrame + UIGridLayout
    │       └── Card_<Nama>.Card
    │           ├── Stage.VehicleImage     ← taruh gambar kendaraan di sini
    │           ├── Stage.PlaceholderIcon  ← hapus kalau sudah pakai gambar
    │           ├── LockOverlay            (kartu terkunci / gamepass)
    │           ├── NewBadge
    │           ├── VehicleName, Info, Status, StatusDot
    └── Details                panel kendaraan yang dipilih
        ├── Stage.VehicleImage
        ├── VehicleName, Info
        ├── Stats.Stat_TopSpeed / Stat_Acceleration / Stat_Handling (Track.Fill)
        └── SpawnButton
```

## Catatan

- **Responsif:** semua ukuran pakai Scale + `UIAspectRatioConstraint` dan teks pakai `TextScaled`, jadi tampilan sama di PC, tablet, dan HP.
- **Tanpa script:** tombol hanya visual (efek hover/klik bawaan dari `AutoButtonColor`). `Main` dan `Backdrop` terlihat secara default. Kalau nanti bikin sistemnya, biasanya `Main.Visible` dan `Backdrop.Visible` diset `false` lalu ditampilkan lewat `OpenButton`.
- **Isi kartu:** gunakan satu kartu sebagai template untuk di-clone (misalnya `Card_BMWR80`). Panjang bar stat diatur lewat `Fill.Size` (Scale X 0–1).
- **Ubah warna/teks/daftar kendaraan:** edit tabel `C`, `VEHICLES`, dan `SELECTED` di atas file `src/VehicleSpawnerGui.luau`, lalu jalankan ulang lewat Command Bar atau build ulang file `.rbxmx`.

## Build ulang `.rbxmx` (opsional)

File `.rbxmx` dibuat dari `src/VehicleSpawnerGui.luau` menggunakan [Lune](https://github.com/lune-org/lune):

```sh
lune run tools/build.luau
```

Untuk render preview PNG: `lune run tools/build.luau -- --tree`, lalu `node tools/preview/render.cjs` (butuh Playwright dan font Montserrat di `build/fonts`, lihat komentar di file tersebut).
