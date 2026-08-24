const COMMAND_PATTERNS = [
  /^(?:open|fetch) (?:[0-9][a-z0-9]{3}|emd[-_]?\d{4,6})$/i,
  /^alphafold [a-z0-9]{6,12}(?:-\d+)?$/i,
  /^blast(?: protein)?$/i,
  /^similar(?: (?:current|[0-9][a-z0-9]{3}))?$/i,
  /^foldseek$/i,
  /^compute (?:esmfold|openfold|boltz)$/i,
  /^style (?:ball|ball&stick|ballandstick|spacefill|spheres|sticks|cartoon|ribbon|backbone|nucleotide|nucleotides|glycan|glycans|thermal|ellipsoid|ellipsoids)$/i,
  /^color (?:element|chain|residue|mono|monochrome)$/i,
  /^label (?:none|off|selected|atoms|residues|chains)$/i,
  /^lighting (?:studio|soft|flat|dramatic)$/i,
  /^view (?:front|back|left|right|top|bottom)$/i,
  /^(?:axes|scalebar|arrow) (?:show|hide)$/i,
  /^clip (?:near|far) [0-9]+(?:\.[0-9]+)?$/i,
  /^surface level -?[0-9]+(?:\.[0-9]+)?$/i,
  /^surface (?:show|hide)$/i,
  /^surface style (?:solid|mesh|dots)$/i,
  /^surface color (?:uniform|element|chain|residue|bfactor|b-factor|charge)$/i,
  /^surface (?:opacity|probe) [0-9]+(?:\.[0-9]+)?$/i,
  /^map style (?:surface|isosurface|volume|solid|slices|slice)$/i,
  /^map (?:smooth|sharpen|zone) [0-9]+(?:\.[0-9]+)?$/i,
  /^map (?:stats|segment|difference)$/i,
  /^map segment -?[0-9]+(?:\.[0-9]+)?$/i,
  /^map reference (?:set|save)$/i,
  /^map crop(?: \d+){6}$/i,
  /^fit (?:map|maps|map-to-map|atoms|structure)$/i,
  /^fit map (?:rotate|rigid)$/i,
  /^(?:undo|redo|addh|hydrogens|charges|dockprep|minimize)$/i,
  /^delete (?:selected|selection|atoms)$/i,
  /^bond (?:add(?: [123])?|delete)$/i,
  /^mutate [a-z]{3}$/i,
  /^chain rename(?: to)? \S+(?: \S+)?$/i,
  /^(?:atom add|addatom) [a-z]{1,2}(?: -?[0-9]+(?:\.[0-9]+)?){3}$/i,
  /^(?:torsion|rotamer) -?[0-9]+(?:\.[0-9]+)?$/i,
  /^tug(?: -?[0-9]+(?:\.[0-9]+)?){3}$/i,
  /^dock analyze$/i,
  /^model (?:loops|gaps|reference|template)$/i,
  /^trajectory (?:play|pause|stop|next|previous|prev)$/i,
  /^trajectory frame [0-9]+$/i,
  /^assembly (?:[a-z0-9]+|asymmetric|asu|none)$/i,
  /^altloc (?:[a-z0-9]+|primary|default|none)$/i,
  /^(?:hbonds|hbond|contacts|clashes|cavities|cavity|interfaces|interface|sequence|conservation)$/i,
  /^interactions clear$/i,
  /^pseudobond (?:add(?: [a-z0-9._-]+)?|clear)$/i,
  /^annotate (?:start|on|stop|off|clear)$/i,
  /^measure (?:area|surface|volume|centroid|center|axis|plane)$/i,
  /^align chains \S+ \S+$/i,
  /^reference (?:set|save|clear)$/i,
  /^(?:rmsd|match) reference$/i,
  /^rmsd (?:trajectory|frame)$/i,
  /^(?:show|hide) (?:atoms|structure|model|map|surface|volume)$/i,
  /^presentation (?:start|on|show|stop|off|exit)$/i,
  /^select (?:all|clear|none|ligand|ligands|water|waters|solvent|chain \S+|residue \S+|resname \S+|element \S+|atom \S+)$/i,
  /^(?:clear|help)$/i,
];

const COMMAND_CATALOG = `MoleculePad commands include: open/fetch PDB or EMDB, alphafold, blast,
similar, foldseek, compute esmfold/openfold/boltz, style, color, label, lighting, view,
axes/scalebar/arrow, clip, surface, map, fit, selection, measurements, interactions,
trajectory, assembly, altloc, sequence analysis, molecular editing, model loops/reference,
annotations, presentation, undo/redo, and help. Return the smallest ordered command list.
Never invent syntax, shell commands, URLs, scripts, aliases, or semicolon-separated commands.`;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function authorized(request, env) {
  if (!env.MOLECULEPAD_ACCESS_TOKEN) return false;
  return request.headers.get("authorization") === `Bearer ${env.MOLECULEPAD_ACCESS_TOKEN}`;
}

async function safetyIdentifier(request) {
  const value = request.headers.get("authorization") || "anonymous";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ status: "ok", protocolVersion: 1 });
    }
    if (request.method !== "POST" || url.pathname !== "/api/copilot") {
      return json({ error: "Not found" }, 404);
    }
    if (!authorized(request, env)) return json({ error: "Unauthorized" }, 401);
    if (!env.OPENAI_API_KEY) return json({ error: "Server model key is not configured" }, 503);

    let input;
    try { input = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
    if (typeof input?.request !== "string" || input.request.length < 1 || input.request.length > 10_000) {
      return json({ error: "Invalid request" }, 400);
    }

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "authorization": `Bearer ${env.OPENAI_API_KEY}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: env.OPENAI_MODEL || "gpt-5.6-luna",
        store: false,
        safety_identifier: await safetyIdentifier(request),
        instructions: `You translate a scientist's plain-language request into safe MoleculePad commands. ${COMMAND_CATALOG}`,
        input: JSON.stringify({ request: input.request, context: input.context || {} }),
        max_output_tokens: 1200,
        text: {
          format: {
            type: "json_schema",
            name: "moleculepad_plan",
            strict: true,
            schema: {
              type: "object",
              properties: {
                summary: { type: "string", minLength: 1, maxLength: 1000 },
                commands: { type: "array", minItems: 1, maxItems: 20, items: { type: "string", minLength: 1, maxLength: 200 } },
              },
              required: ["summary", "commands"],
              additionalProperties: false,
            },
          },
        },
      }),
    });
    if (!response.ok) return json({ error: "Model request failed" }, 502);
    const modelResponse = await response.json();
    const outputText = (modelResponse.output || [])
      .flatMap((item) => item.content || [])
      .find((content) => content.type === "output_text")?.text;
    if (!outputText) return json({ error: "Model returned no plan" }, 502);

    let plan;
    try { plan = JSON.parse(outputText); } catch { return json({ error: "Model returned invalid JSON" }, 502); }
    if (!Array.isArray(plan.commands) || !plan.commands.every((command) =>
      typeof command === "string" && !command.includes(";") && COMMAND_PATTERNS.some((pattern) => pattern.test(command.trim()))
    )) {
      return json({ error: "Plan failed the server allow-list" }, 422);
    }
    return json({ summary: String(plan.summary).slice(0, 2000), commands: plan.commands.map((command) => command.trim()) });
  },
};
