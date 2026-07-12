import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as ed from 'https://esm.sh/@noble/ed25519@2';
import { sha512 } from "https://esm.sh/@noble/hashes@1/sha512";

// Polyfill sync sha512 for noble-ed25519 (Deno needs explicit hash setup)
ed.etc.sha512Sync = (...msgs: Uint8Array[]): Uint8Array => {
  const h = sha512.create();
  for (const m of msgs) h.update(m);
  return h.digest();
};

const PUBLIC_KEY_HEX = Deno.env.get('NUSA_PUBLIC_KEY') ?? '';
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

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

Deno.serve(async (req) => {
  const { key, deviceId } = await req.json();
  if (!key || !deviceId) return json({ error: 'bad_request' }, 400);

  const cleaned = String(key).toUpperCase().replace('NUSA-', '').replace(/-/g, '');
  const serial = cleaned.slice(0, 8);
  const sig = new Uint8Array(b32decode(cleaned.slice(8)));

  // verify signature (Ed25519) offline-style
  const ok = await ed.verify(sig, new TextEncoder().encode(serial), hexToBytes(PUBLIC_KEY_HEX));
  if (!ok) return json({ error: 'invalid_key' }, 403);

  const { data: lic } = await supabase
    .from('licenses').select('id,status').eq('key', key).maybeSingle();
  if (!lic) return json({ error: 'not_found' }, 404);
  if (lic.status === 'revoked') return json({ error: 'revoked' }, 403);

  const { data: existing } = await supabase
    .from('activations').select('id').eq('license_id', (lic as any).id).eq('device_id', deviceId).maybeSingle();
  if (existing) return json({ success: true }, 200);

  const can = await supabase.rpc('can_activate', { lid: (lic as any).id });
  if (!can.data) return json({ error: 'max_devices' }, 409);

  await supabase.from('activations').insert({ license_id: (lic as any).id, device_id: deviceId });
  if ((lic as any).status !== 'activated') {
    await supabase.from('licenses').update({ status: 'activated' }).eq('id', (lic as any).id);
  }
  return json({ success: true }, 200);
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
