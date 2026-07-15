// ============================================================================
// NUSA KASIR — Register Activation Edge Function (v2 — Google Auth)
// Deploy: supabase functions deploy register_activation --project-ref sakeuhcbcnueplzlkltm
// ============================================================================
// Actions:
//   { key, googleUserId }          — activate a license with Google ID
//   { googleUserId } (no key)      — check if Google ID has a license
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as ed from 'https://esm.sh/@noble/ed25519@2';
import { sha512 } from "https://esm.sh/@noble/hashes@1/sha512";

ed.etc.sha512Sync = (...msgs: Uint8Array[]): Uint8Array => {
  const h = sha512.create();
  for (const m of msgs) h.update(m);
  return h.digest();
};

const PUBLIC_KEY_HEX = Deno.env.get('NUSA_PUBLIC_KEY') ?? '';

function b32decode(s: string): number[] {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const map: Record<string, number> = {};
  for (let i = 0; i < alphabet.length; i++) map[alphabet[i]] = i;
  let bits = 0, value = 0; const out: number[] = [];
  for (const ch of s.toUpperCase()) {
    if (!(ch in map)) continue;
    value = (value << 5) | map[ch]; bits += 5;
    if (bits >= 8) { bits -= 8; out.push((value >> bits) & 0xff); }
  }
  return out;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'content-type',
    },
  });
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type' } });
  }

  try {
    const body = await req.json();
    const { key, googleUserId } = body;

    if (!googleUserId) return json({ error: 'googleUserId wajib' }, 400);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // ─── CHECK action (no key provided) ──────────────────────────
    if (!key) {
      const { data: license } = await supabase
        .from('licenses')
        .select('id, key, serial, status, google_user_id, expires_at')
        .eq('google_user_id', googleUserId)
        .maybeSingle();

      if (!license) {
        return json({ has_license: false }, 200);
      }

      // Block revoked/cancelled/suspended licenses — treat as no license
      if (license.status === 'Cancelled' || license.status === 'Suspended' || license.status === 'Expired') {
        return json({
          has_license: false,
          status: license.status,
          message: license.status === 'Cancelled'
            ? 'Lisensi Anda telah dibatalkan.'
            : license.status === 'Suspended'
            ? 'Lisensi Anda sedang dinonaktifkan.'
            : 'Lisensi Anda telah kedaluwarsa.',
        }, 200);
      }

      // Check if trial has expired (via expires_at)
      const isExpired = license.expires_at && new Date(license.expires_at) < new Date();
      if (isExpired && license.status === 'Trial') {
        return json({
          has_license: false,
          status: 'Expired',
          is_expired: true,
          message: 'Masa trial Anda telah berakhir. Silakan beli lisensi penuh.',
        }, 200);
      }

      return json({
        has_license: true,
        license_id: license.id,
        status: license.status,
        key: license.key,
        serial: license.serial,
        expires_at: license.expires_at,
        is_expired: isExpired,
      }, 200);
    }

    // ─── ACTIVATE action (key provided) ──────────────────────────

    // 1. Verify Ed25519 signature
    const cleaned = String(key).toUpperCase().replace('NUSA-', '').replace(/-/g, '');
    const serial = cleaned.slice(0, 8);
    const sig = new Uint8Array(b32decode(cleaned.slice(8)));

    const ok = await ed.verify(sig, new TextEncoder().encode(serial), hexToBytes(PUBLIC_KEY_HEX));
    if (!ok) return json({ error: 'invalid_key' }, 403);

    // 2. Check license
    const { data: lic } = await supabase
      .from('licenses')
      .select('id,status,google_user_id,expires_at')
      .eq('key', key)
      .maybeSingle();

    if (!lic) return json({ error: 'not_found' }, 404);
    if (lic.status === 'Cancelled') return json({ error: 'cancelled', message: 'Key ini sudah dibatalkan' }, 403);
    if (lic.status === 'Suspended') return json({ error: 'suspended', message: 'Key ini sedang dinonaktifkan' }, 403);

    // Accept both 'Generated' and 'Trial' statuses for activation
    if (lic.status !== 'Generated' && lic.status !== 'Trial') {
      return json({ error: 'already_activated', message: 'Key ini sudah diaktivasi' }, 409);
    }

    // 3. Check can_activate
    const can = await supabase.rpc('can_activate', {
      lid: lic.id,
      gid: googleUserId,
    });
    if (!can.data) {
      return json({
        error: 'already_activated',
        message: 'Akun Google ini sudah dipakai untuk license lain. Gunakan license yang sama atau hubungi seller.',
      }, 409);
    }

    // 4. Link Google ID to license
    if (!lic.google_user_id) {
      await supabase
        .from('licenses')
        .update({ google_user_id: googleUserId, status: 'Active' })
        .eq('id', lic.id);
    } else if (lic.status !== 'Active') {
      await supabase
        .from('licenses')
        .update({ status: 'Active' })
        .eq('id', lic.id);
    }

    // 5. Insert activation record
    const { error: insertErr } = await supabase
      .from('activations')
      .insert({
        license_id: lic.id,
        google_user_id: googleUserId,
        device_id: 'android-' + googleUserId.slice(0, 12),
      });

    if (insertErr && insertErr.code === '23505') {
      return json({ success: true, message: 'Sudah teraktivasi sebelumnya', expires_at: lic.expires_at }, 200);
    }
    if (insertErr) {
      return json({ error: 'db_error', message: insertErr.message }, 500);
    }

    return json({ success: true, expires_at: lic.expires_at }, 200);
  } catch (e) {
    return json({ error: 'server_error', message: String(e) }, 500);
  }
});
