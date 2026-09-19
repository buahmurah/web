// =====================================================================
// buahmurah.id — Edge Function "kelola-user"
// Fungsi ini yang membuat akun baru dan mengganti password milik orang lain.
// Kunci service_role hanya hidup di server ini, tidak pernah masuk ke HP.
//
// Cara pasang (paling gampang, tanpa install apa pun):
//   Supabase Dashboard > Edge Functions > Deploy a new function
//   Nama fungsi: kelola-user
//   Tempel seluruh isi file ini, lalu Deploy.
//
// Cara pasang lewat terminal (kalau punya Supabase CLI):
//   supabase functions new kelola-user
//   (timpa isi supabase/functions/kelola-user/index.ts dengan file ini)
//   supabase functions deploy kelola-user
//
// SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY sudah tersedia otomatis,
// tidak perlu diisi manual.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const balas = (isi: unknown, status = 200) =>
  new Response(JSON.stringify(isi), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } }
    );

    // --- Pastikan yang memanggil benar-benar akun manajemen ---
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!token) return balas({ error: "Belum masuk." }, 401);

    const { data: pemanggil, error: eAuth } = await admin.auth.getUser(token);
    if (eAuth || !pemanggil?.user) return balas({ error: "Sesi tidak sah." }, 401);

    const { data: profil } = await admin
      .from("profiles").select("role").eq("id", pemanggil.user.id).single();

    if (profil?.role !== "manajemen")
      return balas({ error: "Hanya akun manajemen yang boleh mengelola pengguna." }, 403);

    const body = await req.json();
    const aksi = body?.aksi;

    // ----------------------------------------------------------------
    if (aksi === "buat") {
      const { email, password, nama, jabatan, role, hak_akses } = body;
      if (!email || !password) return balas({ error: "Email dan password wajib diisi." }, 400);
      if (String(password).length < 6) return balas({ error: "Password minimal 6 karakter." }, 400);

      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          nama: nama ?? "",
          jabatan: jabatan ?? "",
          role: role === "manajemen" ? "manajemen" : "kasir",
          hak_akses: Array.isArray(hak_akses) ? hak_akses : [],
        },
      });
      if (error) return balas({ error: error.message }, 400);

      // Pastikan profil ikut rapi walau trigger belum jalan
      await admin.from("profiles").upsert({
        id: data.user.id,
        email,
        nama: nama ?? "",
        jabatan: jabatan ?? "",
        role: role === "manajemen" ? "manajemen" : "kasir",
        hak_akses: Array.isArray(hak_akses) ? hak_akses : [],
      });

      return balas({ ok: true, id: data.user.id });
    }

    // ----------------------------------------------------------------
    if (aksi === "password") {
      const { id, password } = body;
      if (!id || !password) return balas({ error: "Data tidak lengkap." }, 400);
      if (String(password).length < 6) return balas({ error: "Password minimal 6 karakter." }, 400);

      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) return balas({ error: error.message }, 400);
      return balas({ ok: true });
    }

    // ----------------------------------------------------------------
    if (aksi === "email") {
      const { id, email } = body;
      if (!id || !email) return balas({ error: "Data tidak lengkap." }, 400);

      const { error } = await admin.auth.admin.updateUserById(id, { email, email_confirm: true });
      if (error) return balas({ error: error.message }, 400);
      await admin.from("profiles").update({ email }).eq("id", id);
      return balas({ ok: true });
    }

    // ----------------------------------------------------------------
    if (aksi === "hapus") {
      const { id } = body;
      if (!id) return balas({ error: "Data tidak lengkap." }, 400);
      if (id === pemanggil.user.id) return balas({ error: "Tidak bisa menghapus akun sendiri." }, 400);

      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) return balas({ error: error.message }, 400);
      return balas({ ok: true });
    }

    return balas({ error: "Aksi tidak dikenali." }, 400);
  } catch (e) {
    return balas({ error: String(e?.message ?? e) }, 500);
  }
});
