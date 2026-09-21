# buahmurah.id — Ringkasan Proyek (v7)

> Berkas ini dibuat untuk dilampirkan ke percakapan Claude yang baru supaya pengerjaan
> bisa dilanjutkan tanpa mengulang penjelasan dari nol. Lampirkan file ini bersama
> `index.html` dan `supabase-setup.sql` dari dalam ZIP.

---

## 1. Apa yang sedang dibangun

Aplikasi kasir dan pembukuan untuk **toko buah bernama buahmurah.id**, dipakai dua jenis akun:

- **Akun kasir** — mencatat penjualan dan pengeluaran harian dari HP di kios.
- **Akun manajemen** — pembukuan lengkap, gudang, pengelolaan pengguna, dan menerima
  notifikasi setiap kali kasir menyimpan catatan.

Teknologi: **HTML satu berkas + Supabase** (Auth, Postgres, Realtime, Storage, Edge Function),
dipasang sebagai **PWA**. Tidak ada proses build, tidak ada framework, tidak ada npm. Semua CSS
dan JavaScript ada di dalam `index.html`; library Supabase diambil dari CDN jsdelivr.

Warna wajib: **biru dan kuning**. Bahasa antarmuka: **Indonesia**, termasuk nama variabel dan
fungsi di dalam kode (`muatBuku`, `bukaModal`, `uang()`, `aman()`, `gambarLonceng()`, dst).

---

## 2. Kredensial proyek

**Supabase**

```
URL   : https://uuorhkhpubkvsilsybvw.supabase.co
Key   : sb_publishable_Ers0TipmzhLN-yENqavlBg_tmOU-Vp6   (publishable / anon)
```

Sudah tertulis di bagian KONFIGURASI pada baris awal `<script>` di `index.html`.

**Dua akun login**, dibuat langsung oleh `supabase-setup.sql` bagian 3:

| Email | Role | Jabatan | Kata sandi awal |
|---|---|---|---|
| `panglima@gmail.com` | manajemen | Pemilik | `Panglima2026` |
| `buahmurah.id@gmail.com` | kasir | Kasir | `Kasir2026` |

Ganti kata sandi lewat menu **Akun saya** setelah login pertama.

---

## 3. Spesifikasi asli dari pemilik

**Akun Kasir**

| Modul | Fitur | Keterangan | Satuan |
|---|---|---|---|
| Penjualan | Jenis buah | pilihan | |
| | Qty | pilihan angka | Kg |
| | Harga | isian | |
| | Pembayaran | Cash / Transfer | **wajib dipilih**; bukti transfer opsional |
| | Submit / OK | | |
| Pengeluaran | Keterangan | isian | |
| | Nominal | isian | |
| | Submit / OK | | |

**Akun Manajemen**

| Modul | Kolom |
|---|---|
| Cashflow | Nomor, Tanggal, Keterangan, Debit, Kredit, Saldo, Bukti Transaksi |
| Kulakan | Nomor, Tanggal, Keterangan, Jumlah, Satuan, Harga, Total, Bukti Transaksi — **tanpa debit/kredit**, karena kulakan hanya pengeluaran (revisi pemilik) |
| Gaji | Nomor, Bulan, Absensi/Total Hari, Kasbon, Total |
| Stock Opname | Nomor, Tanggal, Keterangan, Kondisi Baik/Rusak |
| Stock Buah | Jenis Buah, Jumlah, Satuan |

Kolom **Saldo** pada Cashflow tidak disimpan di database, dihitung berjalan di layar
(`saldo += debit - kredit`, diurutkan berdasarkan Nomor). Pada Kulakan yang dihitung adalah
`total = jumlah × harga` per baris, dengan total belanja di baris kaki tabel.

---

## 4. Isi ZIP

```
index.html                      aplikasi utama, satu berkas
manifest.json                   manifest PWA
sw.js                           service worker (cache + notifikasi)
ikon/ikon-192.png               ikon aplikasi
ikon/ikon-512.png
ikon/ikon-maskable-512.png      versi maskable, ada padding aman
ikon/apple-touch-icon.png       untuk iPhone
supabase-setup.sql              seluruh skema database + pembuatan dua akun
edge-function-kelola-user.ts    Edge Function untuk kelola akun
RINGKASAN-PROYEK.md             berkas ini
```

Struktur folder di hosting harus **persis seperti di atas** — `index.html` memanggil
`manifest.json`, `sw.js`, dan folder `ikon/` dengan jalur relatif.

---

## 5. Langkah pemasangan

1. Supabase → SQL Editor → tempel seluruh `supabase-setup.sql` → Run.
   Ini membuat semua tabel, policy, trigger notifikasi, dan dua akun login.
2. Edge Functions → Deploy a new function → nama **persis** `kelola-user` → tempel isi
   `edge-function-kelola-user.ts` → Deploy. Tanpa ini, tombol tambah akun dan ganti kata
   sandi orang lain tidak jalan (aplikasi menawarkan kirim link reset sebagai gantinya).
3. Authentication → Providers → Email → **matikan Confirm email**, supaya akun baru yang
   dibuat dari menu Pengguna langsung bisa masuk.
4. Upload semua berkas ke hosting **HTTPS** (Netlify Drop, Vercel, Cloudflare Pages).
   PWA dan notifikasi tidak jalan lewat `file://` atau HTTP biasa.

---

## 6. Struktur database

| Tabel | Isi | Siapa yang boleh |
|---|---|---|
| `profiles` | id, email, nama, jabatan, role, hak_akses (text[]), aktif | baca diri sendiri; manajemen baca & ubah semua |
| `stock_buah` | jenis_buah, jumlah, satuan, harga, aktif | semua baca; manajemen ubah. **Satu-satunya master buah** — daftar pilihan di layar kasir dibaca dari sini |
| `penjualan` | tanggal, jenis_buah, qty, satuan, harga, total (generated), pembayaran, bukti_url, user_id | kasir hanya miliknya; manajemen semua |
| `pengeluaran` | tanggal, keterangan, nominal, user_id | sama seperti penjualan |
| `cashflow` | nomor, tanggal, keterangan, debit, kredit, bukti_url | khusus manajemen |
| `kulakan` | nomor, tanggal, keterangan, jumlah, satuan, harga, bukti_url | khusus manajemen |
| `gaji` | nomor, nama, bulan, absensi, total_hari, upah_harian, kasbon, total | khusus manajemen |
| `stock_opname` | nomor, tanggal, keterangan, kondisi | khusus manajemen |
| `notifikasi` | judul, pesan, jenis, nominal, untuk_role, ref_tabel, ref_id, dari_nama, dibaca | dibaca oleh role tujuan saja |

Fungsi bantu: `public.my_role()` dan `public.is_manajemen()`, keduanya `security definer`
supaya policy tidak rekursif.

Trigger: `on_auth_user_created` membuat baris `profiles` dari `raw_user_meta_data`;
`on_auth_user_email_change` menyamakan email; `on_penjualan_notif` dan `on_pengeluaran_notif`
menulis baris ke `notifikasi` setiap kali kasir menyimpan.

Storage bucket **`bukti`** (publik) untuk bukti transaksi, dengan awalan folder
`penjualan/`, `cashflow/`, `kulakan/`.

---

## 7. Cara kerja notifikasi

Rantainya: kasir menyimpan → trigger Postgres menulis baris di `notifikasi` →
Supabase Realtime mengirim event INSERT → `index.html` menangkapnya lewat
`sb.channel("notifikasi-masuk")` → memanggil `registration.showNotification()`.

Yang tampil di layar manajemen: lonceng dengan angka belum dibaca di sidebar dan di
bilah atas HP, panel daftar 50 notifikasi terakhir, tombol tandai semua sudah dibaca,
dan toast di dalam aplikasi. Mengetuk notifikasi HP membuka menu Data Penjualan atau
Data Pengeluaran lewat `postMessage` dari service worker.

Izin notifikasi diminta lewat tombol (bukan otomatis saat muat), sesuai syarat browser.
Tawaran muncul sekali saja untuk akun manajemen, dan bisa diaktifkan kapan saja dari
menu **Akun saya** atau dari panel lonceng.

**Batasannya:** notifikasi muncul selama aplikasi masih berjalan, termasuk saat berada di
latar belakang. Kalau aplikasi benar-benar ditutup, notifikasi tidak masuk. Untuk itu
dibutuhkan Web Push sungguhan — kunci VAPID plus pengirim di Edge Function. Handler `push`
di `sw.js` sudah disiapkan untuk itu, tinggal menambah tabel langganan push dan pengirimnya.

---

## 8. Yang sudah selesai

**Autentikasi.** Login email + password, sesi bertahan, lupa kata sandi lewat link reset.
Adapter penyimpanan sesi dibungkus try/catch supaya tidak pecah tanpa `localStorage`.

**Menu berdasar hak akses.** `SEMUA_MENU` memuat seluruh menu beserta ikon dan grup;
`BAWAAN` memuat menu bawaan per role. Kalau `profiles.hak_akses` kosong, dipakai bawaan
role. Menu bertanda `khususManajemen` selalu disembunyikan dari akun kasir.

**Penjualan.** Pilih buah → harga terisi otomatis, stepper +/− 0,5 Kg, total besar di bar
kuning. Cash atau Transfer wajib dipilih; kalau belum, tombol simpan menolak dan kotak
pilihan diberi garis merah. Memilih Transfer memunculkan kotak bukti dengan dua tombol:
**Ambil foto** (`capture="environment"`, kamera langsung terbuka) dan **Pilih berkas**
(galeri atau berkas). Keduanya opsional dan saling meniadakan.

**Pengeluaran, Riwayat, Cashflow, Gaji, Stock Opname, Data kasir** — sesuai tabel
spesifikasi, dengan nomor otomatis, saldo berjalan, dan unggah bukti.

**Kulakan** memakai kolom Jumlah, Satuan, dan Harga; total per baris dan total belanja
dihitung di layar. Keterangan punya `datalist` berisi nama buah dari Stock Buah, dan
memilih salah satunya ikut mengisi satuannya.

**Stock Buah** adalah master tunggal: jumlah, satuan, harga jual, dan saklar "tampil di
kasir" semuanya bisa diedit langsung di tabel. Layar kasir membaca daftar buah dari sini,
lengkap dengan sisa stok di tiap pilihan — jadi tidak ada lagi buah yang muncul di kasir
tapi sudah dihapus manajemen.

**Form bersama Tambah & Ubah.** Setiap tabel manajemen punya satu definisi di
`FORM[tabel]`, dan definisi itu dipakai oleh form Tambah (panel di atas tabel) maupun form
Ubah (modal dari tombol Ubah per baris). Jadi isiannya dijamin identik — sudah diuji
otomatis untuk cashflow, kulakan, gaji, stock opname, dan stock buah. Menambah kolom cukup
dengan menambah satu entri di `FORM`.

Jenis isian yang didukung: `teks` (bisa `saran:"buah"` untuk datalist stok), `tanggal`,
`bulan`, `angka`, `uang`, `pilih`, `cek`, `pilihBuah` (dropdown dari stok, mengisi satuan
dan harga), `bayar` (tombol Cash/Transfer), `total` (tampilan hitung langsung lewat
`rumus`), dan `bukti`. Opsi tambahan: `wajib`, `lebihDariNol`, `lebar`, `bawaan`,
`nomorOtomatis`, `tampilJika(v)`, serta `otomatis(v)` + `dari:[...]` untuk isian yang
dihitung ulang saat isian lain berubah (dipakai total gaji).

Isian `bukti` di form Ubah menampilkan pratinjau bukti lama, kotak centang **Hapus bukti
ini**, dan tombol Ambil foto / Pilih berkas untuk menggantinya. Aturan simpannya: ada
berkas baru → diunggah dan menggantikan; dicentang hapus → `null`; tidak disentuh →
kolom tidak ikut dikirim sehingga bukti lama tetap; bukti tersembunyi oleh `tampilJika`
(misalnya penjualan diganti ke Cash) → `null`.

Data Penjualan dan Data Pengeluaran juga punya definisi di `FORM` yang meniru layar kasir,
jadi manajemen mengubahnya dengan isian yang sama seperti saat kasir mencatat.

Fungsi inti: `htmlForm`, `pasangForm`, `bacaForm`, `nilaiAwal`, `ubahDenganForm`,
`layarDenganForm`, `pasangUbah(tabel, data, muatUlang, judul)`.

**Stok otomatis.** Trigger `on_penjualan_stok` memotong `stock_buah.jumlah` setiap kali
kasir menyimpan penjualan, mengembalikannya saat baris dihapus, dan menghitung selisihnya
saat jumlah atau jenis buah diubah. Sisa stok ikut ditampilkan di tiap pilihan buah pada
layar kasir dan disegarkan setiap selesai menyimpan. Kalau jumlah jual melebihi stok
tercatat, muncul peringatan tapi transaksi tetap disimpan — supaya kasir tidak terhambat
ketika pencatatan stok belum rapi.

**Filter tanggal.** Data Penjualan, Data Pengeluaran, dan Riwayat kasir memakai satu
komponen filter yang sama: Hari ini, Kemarin, 7 hari, Bulan ini, dan Rentang tanggal.
Bawaannya Hari ini. Fungsinya `buatFilter()`, `kotakFilter(pre)`, `pasangFilter(pre, st,
muatUlang)`, dan `labelRentang(st)`.

**Panel notifikasi.** Bilah berisi jumlah belum dibaca dan tombol "Tandai semua dibaca"
menempel di atas panel (`position:sticky`), jadi tidak perlu scroll ke bawah. Daftar
menampilkan 7 notifikasi, lalu tombol "Lihat N notifikasi lainnya" menambah 7 lagi setiap
diklik (hingga 100 yang dimuat). Mengetuk satu notifikasi menandainya sudah dibaca dan
langsung membuka Data Penjualan atau Data Pengeluaran. Konstanta: `LANGKAH_NOTIF = 7`.

**Tata letak HP.** Semua grid memakai `minmax(0,1fr)`, bukan `1fr`, supaya dropdown dengan
nama buah panjang tidak memaksa halaman melebar. Semua isian bertulisan 16px di layar ≤960px
supaya Safari iPhone tidak memperbesar layar saat isian disentuh. Tanggal di header memakai
format pendek di layar sempit. Sudah diuji tanpa geser samping di lebar 360 dan 390 piksel.

**Header dan navigasi.** Setiap halaman punya header berisi sapaan dengan nama yang login,
tanggal dan jam berjalan (diperbarui tiap detik), lonceng notifikasi, dan avatar bundar
berisi inisial. Avatar diklik memunculkan pop-up profil dengan tombol Akun saya dan Keluar.
Panel kiri punya header berisi logo dan nama aplikasi. Di HP, bilah bawah hanya memuat
lima tombol: empat menu utama sesuai role plus **Lainnya**, yang membuka sisanya dalam
bentuk kisi. Semua ikon memakai SVG garis tipis, bukan emoji.

**Pengguna** (khusus manajemen). Tambah akun, ubah nama/jabatan/email/role/hak akses,
ganti kata sandi, hapus akun.

**Format ribuan.** Semua isian nominal memakai `class="uang"`; `pasangUang()` memformat
saat diketik sambil menjaga posisi kursor, `uang(selector)` mengembalikan angka murni.
Panggil `siapkanUang()` setiap selesai merender layar.

**PWA.** Saat aplikasi pertama dibuka muncul dialog **Instal / Nanti saja**. Pilihan
"Nanti saja" disimpan dan baru ditanya lagi tiga hari kemudian. Di iPhone, dialog berubah
jadi panduan manual karena Safari tidak menyediakan `beforeinstallprompt`. Service worker
memakai network-first untuk halaman dan cache-first untuk aset; permintaan ke domain
`supabase.co` tidak pernah di-cache.

---

## 9. Konvensi kode

- Semua nama fungsi dan variabel berbahasa Indonesia.
- Pola layar: `layarX()` merender HTML ke `#layar`, lalu `muatX()` mengisi tabelnya.
  Setelah render selalu panggil `siapkanUang()`.
- Ikon: `ikon(nama, ukuran)` mengambil path dari `GAMBAR_IKON` dan membungkusnya jadi SVG
  `stroke="currentColor"`. Menambah menu berarti menambah satu entri di `SEMUA_MENU`
  (dengan `pendek` untuk label bilah bawah) dan satu path di `GAMBAR_IKON`.
- Bukti transaksi: `kotakBukti(pre)` merender tombol kamera + berkas, `pasangBukti(pre)`
  mengikatnya, `unggahBukti(pre, folder)` mengunggah ke Storage lalu mengembalikan `{url}`
  atau `{error}`, `resetBukti(pre)` mengosongkan.
- Fungsi bantu: `$()`, `rp()`, `angka()`, `tglIndo()`, `hariIni()`, `bulanIni()`,
  `aman()` untuk escape HTML, `toast()`, `pasangHapus(tabel, muatUlang)`, dan
  `bukaModal(judul, isiHTML, saatSimpan, labelTombol)` — kalau `saatSimpan` diisi `null`,
  tombol Simpan disembunyikan dan Batal berubah jadi Tutup.
- Semua input pengguna yang masuk ke HTML wajib lewat `aman()`.
- Token warna di `:root`: `--biru-tua #0A3D91`, `--biru #1157C7`, `--kuning #FFC91D`,
  `--biru-kabut #E7F0FF`, `--bg #F4F7FC`, `--tinta #0E1B33`. Kuning hanya untuk aksi dan
  angka penting, bukan hiasan.
- Font Plus Jakarta Sans, angka memakai `font-variant-numeric: tabular-nums`.
- Sidebar di layar lebar, tab bawah di layar ≤960px, padding `env(safe-area-inset-*)`.
- Kolom grid selalu `minmax(0,1fr)`; isian di HP minimal 16px. Melanggar salah satunya
  membuat layar HP melebar atau ter-zoom.
- **Naikkan angka `VERSI` di `sw.js` setiap kali `index.html` diubah**, kalau tidak HP
  akan tetap membuka versi lama dari cache. Sekarang bernilai `buahmurah-v6`.

---

## 10. Yang belum dikerjakan

1. **Web Push sungguhan** supaya notifikasi tetap masuk saat aplikasi tertutup — perlu
   kunci VAPID, tabel langganan push, dan pengirim di Edge Function.
2. **Kulakan belum menambah stok.** Penjualan sudah memotong stok otomatis, tapi kulakan
   belum menambahnya, karena kolom Keterangan masih teks bebas dan satuannya sering beda
   (peti vs Kg). Perlu kolom `jenis_buah` tersendiri di tabel kulakan plus faktor konversi
   satuan sebelum ini bisa otomatis.
3. **Laporan dan ekspor.** Belum ada rekap per periode, grafik, atau unduh Excel/PDF.
5. **Edit baris pembukuan.** Cashflow, kulakan, gaji, dan opname hanya bisa ditambah dan
   dihapus, belum bisa diedit.
6. **Kolom `profiles.aktif`** sudah ada tapi belum dipakai untuk menonaktifkan akun.
7. **Berkas bukti lama tidak ikut terhapus dari Storage** saat diganti atau dihapus —
   hanya tautannya yang dilepas dari baris. Perlu policy delete di `storage.objects`
   plus pemanggilan `remove()` kalau ingin benar-benar bersih.
8. **Antrean offline.** Aplikasi tetap terbuka tanpa sinyal, tapi menyimpan transaksi
   masih butuh internet.
9. **Pencarian teks** pada tabel data belum ada (filter tanggal sudah). Hasil query
   dibatasi 300–500 baris per rentang.
10. **Cashflow dan Kulakan belum berfilter tanggal** — keduanya masih menampilkan seluruh
   buku karena saldo berjalan perlu dihitung dari awal.

---

## 11. Cara memakai ringkasan ini di chat baru

Kalimat pembuka yang disarankan:

> Aku sedang membangun buahmurah.id, aplikasi kasir dan pembukuan toko buah dengan
> HTML satu berkas + Supabase, dipasang sebagai PWA. Ini ringkasan proyeknya dan berkas
> kodenya. Tolong lanjutkan dengan [sebutkan yang mau dikerjakan]. Ikuti konvensi di
> bagian 9, pertahankan bahasa Indonesia dan warna biru-kuning.

Lampirkan `RINGKASAN-PROYEK.md`, `index.html`, dan `supabase-setup.sql`.
