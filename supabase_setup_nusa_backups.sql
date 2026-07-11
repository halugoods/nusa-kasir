-- ============================================================
-- NUSA Kasir — Setup Supabase Storage bucket "nusa-backups"
-- Jalankan di: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- CATATAN KEAMANAN:
-- App akses Supabase pakai anon key (TANPA user login).
-- Maka policy dibuat untuk role 'anon' + 'authenticated'.
-- Path file = {activation_key_sanitized}/backup.sqlite.enc
--   - activation_key itu rahasia (cuma pemilik yang tau)
--   - file sendiri terenkripsi AES-256-GCM (kunci = SHA-256(key))
--   → orang lain gak bisa decrypt walau kebetulan nemu path.
--
-- ============================================================

-- 1. Buat bucket (private)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'nusa-backups',
  'nusa-backups',
  false,
  52428800,
  ARRAY['application/octet-stream']
)
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = 52428800,
      allowed_mime_types = ARRAY['application/octet-stream'];

-- 2. Enable RLS
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 3. Drop old policies (idempotent)
DROP POLICY IF EXISTS "nusa_backups_insert" ON storage.objects;
DROP POLICY IF EXISTS "nusa_backups_select" ON storage.objects;
DROP POLICY IF EXISTS "nusa_backups_update" ON storage.objects;
DROP POLICY IF EXISTS "nusa_backups_delete" ON storage.objects;

-- 4. INSERT — anon + authenticated boleh upload ke bucket ini
CREATE POLICY "nusa_backups_insert" ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'nusa-backups');

-- 5. SELECT — anon + authenticated boleh download dari bucket ini
CREATE POLICY "nusa_backups_select" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'nusa-backups');

-- 6. UPDATE — anon + authenticated boleh upsert
CREATE POLICY "nusa_backups_update" ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (bucket_id = 'nusa-backups')
  WITH CHECK (bucket_id = 'nusa-backups');

-- 7. DELETE — anon + authenticated boleh hapus
CREATE POLICY "nusa_backups_delete" ON storage.objects
  FOR DELETE TO anon, authenticated
  USING (bucket_id = 'nusa-backups');

-- ============================================================
-- Verify
-- ============================================================
SELECT id, name, public FROM storage.buckets WHERE id = 'nusa-backups';
