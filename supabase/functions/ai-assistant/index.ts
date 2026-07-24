// Supabase Edge Function: ai-assistant
//
// Receives chat messages + optional store context, forwards to an LLM,
// and returns the assistant reply.
//
// Deploy: supabase functions deploy ai-assistant
//
// Environment variables (set via Supabase Dashboard → Edge Functions):
//   OPENROUTER_API_KEY  – OpenRouter API key (https://openrouter.ai/keys)
//   OPENROUTER_MODEL    – default model (e.g. "google/gemini-2.0-flash-001")
//   OPENAI_API_KEY      – optional, fallback to OpenAI
//   SYSTEM_PROMPT       – optional, overrides the built-in prompt

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";

// ── Default system prompt ──────────────────────────────────────────
const DEFAULT_SYSTEM_PROMPT = `Kamu adalah AI Assistant untuk NUSA Kasir, aplikasi Point of Sale (POS) untuk toko kelontong, UMKM, dan retail di Indonesia.

Kamu bisa membantu pemilik toko dengan:
- Analisis data penjualan dan tren bisnis
- Tips mengelola stok, karyawan, dan keuangan
- Cara menggunakan fitur-fitur NUSA Kasir (produk, transaksi, pelanggan, promosi, laporan, absensi, keuangan, dll)
- Strategi meningkatkan omzet dan efisiensi toko
- Menjelaskan laporan laba rugi, arus kas, dan metrik bisnis
- Rekomendasi produk yang perlu di-restock berdasarkan data penjualan

Gaya bicara: santai, ramah, dan profesional. Gunakan bahasa Indonesia yang natural (campuran formal dan gaul secukupnya). Berikan jawaban yang actionable dan praktis, bukan teori kosong.

Jika ditanya hal di luar konteks bisnis/POS/NUSA Kasir, arahkan kembali ke topik yang relevan dengan sopan.`;

// ── Model mapping ──────────────────────────────────────────────────
const MODEL_ALIASES: Record<string, string> = {
  "gemini": "google/gemini-2.0-flash-001",
  "gpt4": "openai/gpt-4o",
  "gpt4-mini": "openai/gpt-4o-mini",
  "claude": "anthropic/claude-3.5-sonnet",
  "deepseek": "deepseek/deepseek-chat",
  "llama": "meta-llama/llama-4-maverick:free",
};

function resolveModel(requested?: string): string {
  if (!requested) {
    return Deno.env.get("OPENROUTER_MODEL") ?? "google/gemini-2.0-flash-001";
  }
  return MODEL_ALIASES[requested] ?? requested;
}

// ── Main handler ───────────────────────────────────────────────────
serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const messages: { role: string; content: string }[] = body.messages ?? [];
    const storeName: string | undefined = body.store_name;
    const modelAlias: string | undefined = body.model;
    const model = resolveModel(modelAlias);

    if (messages.length === 0) {
      return new Response(
        JSON.stringify({ reply: "Tidak ada pesan yang dikirim." }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const systemPrompt = Deno.env.get("SYSTEM_PROMPT") ?? DEFAULT_SYSTEM_PROMPT;

    // Build context-aware system prompt
    let fullSystemPrompt = systemPrompt;
    if (storeName) {
      fullSystemPrompt = `Konteks: kamu sedang membantu pemilik toko "${storeName}".\n\n${systemPrompt}`;
    }

    // Build message array with system prompt
    const apiMessages = [
      { role: "system", content: fullSystemPrompt },
      ...messages,
    ];

    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ reply: "⚠️ AI Assistant belum dikonfigurasi. Admin perlu menambahkan OPENROUTER_API_KEY di Supabase Edge Function settings." }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Call OpenRouter API
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://nusa-kasir.app",
        "X-Title": "NUSA Kasir AI Assistant",
      },
      body: JSON.stringify({
        model,
        messages: apiMessages,
        max_tokens: 1024,
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error(`OpenRouter error ${response.status}:`, err);

      // Try OpenAI fallback if configured
      const openaiKey = Deno.env.get("OPENAI_API_KEY");
      if (openaiKey) {
        const oaiResp = await fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${openaiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "gpt-4o-mini",
            messages: apiMessages,
            max_tokens: 1024,
            temperature: 0.7,
          }),
        });
        if (oaiResp.ok) {
          const oaiData = await oaiResp.json();
          const reply = oaiData.choices?.[0]?.message?.content
            ?? "Maaf, tidak ada jawaban dari AI.";
          return new Response(
            JSON.stringify({ reply }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
      }

      return new Response(
        JSON.stringify({ reply: `Maaf, AI Assistant sedang sibuk (error ${response.status}). Coba lagi nanti.` }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const data = await response.json();
    const reply = data.choices?.[0]?.message?.content
      ?? "Maaf, tidak ada jawaban dari AI.";

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("ai-assistant error:", err);
    return new Response(
      JSON.stringify({ reply: `⚠️ Gagal memproses: ${err instanceof Error ? err.message : "unknown error"}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
