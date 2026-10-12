let graphData;
let cy;
let selectedSourceId = "workload:web-pod";

const typeLabels = {
  workload: "Workload",
  service_account: "Service account",
  iam_role: "IAM role",
  principal: "Trust principal",
  permission: "Permission",
  s3_bucket: "S3 bucket",
  s3_object: "S3 object",
};

const sourceTypes = new Set(["workload", "service_account", "iam_role"]);
let tooltipHideTimer;
let hoveredNodeId;

const typeColors = {
  workload: "#ff8f70",
  service_account: "#d7a7ff",
  iam_role: "#67b7ff",
  principal: "#aabbd4",
  permission: "#7186a5",
  s3_bucket: "#67d7ae",
  s3_object: "#ffd166",
};

const layerDefinitions = [
  { id: "layer-workloads", label: "WORKLOADS", types: ["workload"] },
  { id: "layer-identities", label: "IDENTITIES & TRUST", types: ["service_account", "iam_role", "principal"] },
  { id: "layer-storage", label: "STORAGE", types: ["s3_bucket", "s3_object"] },
];

function permissionDetails(data) {
  return `${data.action || "permission"} on ${(data.resource || "resource").replace("arn:aws:s3:::", "")}`;
}

function permissionEdges(data) {
  const permissions = data.nodes.filter((node) => node.type === "permission");
  const integrated = [];
  const seen = new Set();
  permissions.forEach((permission) => {
    const source = data.edges.find(
      (edge) => edge.relation === "has_permission" && edge.target === permission.id
    )?.source;
    const accessEdge = data.edges.find(
      (edge) =>
        edge.relation === "can_access" &&
        edge.source === source &&
        edge.action === permission.action &&
        edge.resource === permission.resource
    );
    const target = accessEdge?.target;
    if (!source || !target) return;
    const key = `${source}|${target}|${permission.action}|${permission.resource}`;
    if (seen.has(key)) return;
    seen.add(key);
    integrated.push({
      id: `integrated-permission-${integrated.length}`,
      source,
      target,
      relation: permission.action === "sts:AssumeRole" ? "can_assume_role" : "can_access",
      action: permission.action,
      resource: permission.resource,
      policy: permission.policy,
      permissionId: permission.id,
    });
  });
  return integrated;
}

function permissionRecordsForNode(nodeId) {
  const permissionNodes = graphData.nodes.filter((node) => node.type === "permission");
  const permissionById = new Map(permissionNodes.map((permission) => [permission.id, permission]));
  const resourceIds = new Set([nodeId]);
  const node = graphData.nodes.find((candidate) => candidate.id === nodeId);
  if (node?.type === "s3_object") {
    graphData.edges
      .filter((edge) => edge.relation === "contains" && edge.target === nodeId)
      .forEach((edge) => resourceIds.add(edge.source));
  }

  return graphData.edges
    .filter((edge) => edge.relation === "has_permission" && edge.source === nodeId)
    .map((edge) => permissionById.get(edge.target))
    .concat(
      graphData.edges
        .filter((edge) => edge.relation === "can_access" && resourceIds.has(edge.target))
        .map((accessEdge) =>
          permissionNodes.find(
            (permission) =>
              graphData.edges.some(
                (edge) =>
                  edge.relation === "has_permission" &&
                  edge.source === accessEdge.source &&
                  edge.target === permission.id
              ) &&
              permission.action === accessEdge.action &&
              permission.resource === accessEdge.resource
          )
        )
    )
    .filter(Boolean)
    .filter((permission, index, permissions) =>
      permissions.findIndex((candidate) => candidate.id === permission.id) === index
    );
}

function appendPermissionDetails(details, nodeId) {
  const permissions = permissionRecordsForNode(nodeId);
  if (!permissions.length) return;
  const row = document.createElement("div");
  const label = document.createElement("dt");
  const list = document.createElement("dd");
  label.textContent = "Permissions";
  const items = document.createElement("ul");
  permissions.forEach((permission) => {
    const item = document.createElement("li");
    item.textContent = permissionDetails(permission);
    items.append(item);
  });
  list.append(items);
  row.append(label, list);
  details.append(row);
}

function showDetails(data, nodeId) {
  const details = document.getElementById("details");
  details.replaceChildren();
  Object.entries(data).forEach(([key, value]) => {
    if (key === "parent") return;
    const row = document.createElement("div");
    const label = document.createElement("dt");
    const content = document.createElement("dd");
    label.textContent = key;
    content.textContent = typeof value === "object" ? JSON.stringify(value) : String(value);
    row.append(label, content);
    details.append(row);
  });
  if (nodeId) appendPermissionDetails(details, nodeId);
}

function layerFor(type) {
  return layerDefinitions.find((layer) => layer.types.includes(type))?.id;
}

function displayName(id) {
  return id.split(":").slice(-1)[0];
}

function wrapText(value, maxLength = 20) {
  return String(value)
    .split("\n")
    .map((line) => {
      const words = line.split(/(?=[/:.*_-])|(\s+)/).filter(Boolean);
      const lines = [];
      let current = "";
      words.forEach((word) => {
        if (current && current.length + word.length > maxLength) {
          lines.push(current);
          current = "";
        }
        current += word;
      });
      if (current) lines.push(current);
      return lines.join("\n");
    })
    .join("\n");
}

function nodeLabel(element) {
  const data = element.data();
  if (data.type === "permission") {
    const resource = (data.resource || "").replace("arn:aws:s3:::", "");
    return [data.action || "permission", resource]
      .filter(Boolean)
      .map((value) => wrapText(value, 18))
      .join("\n");
  }
  return wrapText(data.name || "", data.type === "iam_role" ? 18 : 20);
}

function edgeLabel(element) {
  const data = element.data();
  if (data.action && data.resource) return `${data.action} on ${data.resource.replace("arn:aws:s3:::", "")}`;
  const labels = {
    uses_service_account: "runs as",
    maps_to_role: "maps to IAM role",
    trusts: "trusts",
    has_permission: data.action ? `allows ${data.action}` : "allows",
    can_assume_role: "can assume role",
    can_access: data.action ? `${data.action} on` : "can access",
    contains: "contains",
  };
  return labels[data.relation] || data.relation || "";
}

function riskForNode(node) {
  if (node.type === "service_account") return "identity";
  if (node.type === "principal") return "takeover";
  if (node.type === "workload" && node.tier === "public") return "normal";
  if (node.type === "s3_bucket" && node.name === "cloud-twin-public") return "normal";
  if (node.type === "s3_object" && node.bucket === "cloud-twin-public") return "normal";
  if (node.type === "iam_role" && node.name === "cloud-twin-api-role") return "takeover";
  if (node.type === "iam_role" || node.type === "permission") return "backend";
  return "backend";
}

function elementsForGraph(data) {
  const layers = layerDefinitions.map((layer) => ({
    data: { id: layer.id, label: layer.label, type: "layer" },
    classes: "layer",
  }));
  const nodes = data.nodes.filter((node) => node.type !== "permission").map((node) => ({
    data: { ...node, parent: layerFor(node.type), risk: riskForNode(node) },
  }));
  const visibleEdges = data.edges.filter((edge) => edge.relation !== "has_permission" && edge.relation !== "can_access");
  const edges = [...visibleEdges, ...permissionEdges(data)].map((edge, index) => ({
    data: { ...edge, id: `edge-${index}`, risk: edge.relation === "can_assume_role" || edge.relation === "trusts" ? "takeover" : edge.relation === "maps_to_role" ? "identity" : "backend" },
  }));
  return [...layers, ...nodes, ...edges];
}

function graphPositions(data) {
  const positions = {};
  const layerX = {
    "layer-workloads": 160,
    "layer-identities": 520,
    "layer-storage": 880,
  };
  const counts = {};
  data.nodes.forEach((node) => {
    const layer = layerFor(node.type);
    const index = counts[layer] || 0;
    counts[layer] = index + 1;
    positions[node.id] = {
      x: layerX[layer],
      y: 150 + index * 145,
    };
  });
  return positions;
}

function graphStyles() {
  return [
    {
      selector: "node.layer",
      style: {
        label: "data(label)",
        shape: "roundrectangle",
        "background-color": "#101827",
        "background-opacity": 0,
        "border-color": "#3b5578",
        "border-width": 2,
        color: "#91a7c5",
        "font-size": 11,
        "font-weight": "bold",
        "text-valign": "top",
        "text-halign": "left",
        "text-margin-x": 12,
        "text-margin-y": 10,
        padding: 28,
        "compound-sizing-wrt-labels": "include",
      },
    },
    {
      selector: "node[type]",
      style: {
        label: nodeLabel,
        "background-color": (element) => typeColors[element.data("type")] || "#8294ad",
        color: "#eef5ff",
        "font-size": 13,
        "font-weight": "bold",
        "text-wrap": "wrap",
        "text-max-width": 135,
        "text-events": "yes",
        "text-outline-color": "#101827",
        "text-outline-width": 2,
        "text-valign": "bottom",
        "text-margin-y": 8,
        width: 34,
        height: 34,
        "border-width": 2,
        "border-color": "#d9e8ff",
      },
    },
    { selector: 'node[type="workload"]', style: { shape: "roundrectangle", width: 48, height: 34 } },
    { selector: 'node[type="service_account"]', style: { shape: "diamond", width: 38, height: 38 } },
    { selector: 'node[type="iam_role"]', style: { shape: "hexagon", width: 44, height: 40 } },
    { selector: 'node[type="principal"]', style: { shape: "ellipse", "border-style": "dashed", width: 30, height: 30 } },
    { selector: 'node[type="permission"]', style: { shape: "rectangle", width: 138, height: 60, "border-style": "dotted", "font-size": 12, "text-max-width": 126, "text-valign": "center", "text-margin-y": 0 } },
    { selector: 'node[type="s3_bucket"]', style: { shape: "barrel", width: 44, height: 42 } },
    { selector: 'node[type="s3_object"]', style: { shape: "roundrectangle", width: 38, height: 30 } },
    { selector: 'node[risk="normal"]', style: { "border-color": "#67d7ae" } },
    { selector: 'node[risk="backend"]', style: { "border-color": "#67b7ff" } },
    { selector: 'node[risk="identity"]', style: { "border-color": "#d7a7ff" } },
    { selector: 'node[risk="takeover"]', style: { "border-color": "#ff6b8a" } },
    {
      selector: "edge",
      style: {
        width: 1.5,
        "line-color": "#58708f",
        "target-arrow-color": "#58708f",
        "target-arrow-shape": "triangle",
        "curve-style": "bezier",
        label: edgeLabel,
        color: "#f1f6ff",
        "font-size": 11,
        "text-rotation": "autorotate",
        "text-outline-width": 0,
      },
    },
    { selector: 'edge[risk="takeover"]', style: { "line-color": "#ff6b8a", "target-arrow-color": "#ff6b8a", width: 2.5 } },
    { selector: 'edge[risk="identity"]', style: { "line-color": "#d7a7ff", "target-arrow-color": "#d7a7ff", width: 2 } },
    { selector: ".highlighted", style: { "border-width": 4, "border-color": "#ffffff", "line-color": "#73d0ff", "target-arrow-color": "#73d0ff", width: 4, opacity: 1 } },
    { selector: ".faded", style: { opacity: 0.42 } },
  ];
}

function highlightPath(path) {
  cy.elements().removeClass("highlighted faded");
  const nodeIds = new Set(path.nodes);
  cy.elements().forEach((element) => {
    if (element.isNode() && nodeIds.has(element.id())) element.addClass("highlighted");
    else if (element.isEdge() && nodeIds.has(element.data("source")) && nodeIds.has(element.data("target"))) element.addClass("highlighted");
    else element.addClass("faded");
  });
}

function renderPaths() {
  const list = document.getElementById("paths");
  list.replaceChildren();
  const sourceData = graphData.reachability?.[selectedSourceId];
  const paths = sourceData ? sourceData.paths : graphData.predictedPaths;
  paths.forEach((path) => {
    const item = document.createElement("li");
    item.textContent = path.nodes.map(displayName).join(" → ");
    item.addEventListener("click", () => highlightPath(path));
    list.append(item);
  });
}

function renderSourcePicker() {
  const select = document.getElementById("sourceSelect");
  select.replaceChildren();
  const sourceNodes = graphData.nodes.filter((node) => sourceTypes.has(node.type));
  sourceNodes.forEach((node) => {
    const option = document.createElement("option");
    option.value = node.id;
    option.textContent = `${typeLabels[node.type] || node.type}: ${node.name || node.id}`;
    option.selected = node.id === selectedSourceId;
    select.append(option);
  });
  const selectedNode = graphData.nodes.find((node) => node.id === selectedSourceId);
  if (!selectedNode || !sourceTypes.has(selectedNode.type) || !graphData.reachability?.[selectedSourceId]) {
    selectedSourceId = sourceNodes.find((node) => node.id === "workload:web-pod")?.id || sourceNodes[0]?.id;
    select.value = selectedSourceId;
  }
}

function highlightReachability(sourceId) {
  const sourceData = graphData.reachability?.[sourceId];
  if (!sourceData) return;
  const reachable = new Set([sourceId, ...sourceData.reachableNodes]);
  const pathEdges = new Set(
    sourceData.paths.flatMap((path) =>
      path.edges.map((edge) => `${edge.source}|${edge.relation}|${edge.target}`)
    )
  );
  cy.elements().removeClass("highlighted faded");
  cy.elements().forEach((element) => {
    if (element.isNode() && reachable.has(element.id())) {
      element.addClass("highlighted");
    } else if (
      element.isEdge() &&
      (pathEdges.has(`${element.data("source")}|${element.data("relation")}|${element.data("target")}`) ||
        (reachable.has(element.data("source")) && reachable.has(element.data("target"))))
    ) {
      element.addClass("highlighted");
    } else {
      element.addClass("faded");
    }
  });
  renderPaths();
  updateStatus(`${sourceData.reachableNodes.length} reachable entities from ${displayName(sourceId)}.`);
}

function updateStatus(message) {
  if (!graphData) {
    document.getElementById("status").textContent = message || "Loading graph…";
    return;
  }
  const metadata = graphData._metadata?.updatedAt ? ` · updated ${new Date(Number(graphData._metadata.updatedAt) / 1000000).toLocaleTimeString()}` : "";
  document.getElementById("status").textContent = message || `${graphData.nodes.length} nodes · ${graphData.edges.length} edges · ${graphData.predictedPaths.length} predicted paths${metadata}`;
}

function renderGraph() {
  if (cy) cy.destroy();
  cy = cytoscape({
    container: document.getElementById("cy"),
    elements: elementsForGraph(graphData),
    style: graphStyles(),
    layout: { name: "preset", positions: graphPositions(graphData), fit: true, padding: 90 },
    userZoomingEnabled: false,
  });
  cy.on("tap", "node[type]", (event) => showDetails(event.target.data(), event.target.id()));
  cy.on("tap", "edge", (event) => showDetails(event.target.data()));
  cy.on("mouseover", "node[type]", (event) => showNodeTooltip(event.target));
  cy.on("mouseout", "node[type]", scheduleTooltipHide);
  updateStatus();
  renderSourcePicker();
  renderPaths();
}

function showNodeTooltip(node) {
  clearTimeout(tooltipHideTimer);
  hoveredNodeId = node.id();
  const tooltip = document.getElementById("graphTooltip");
  const permissions = permissionRecordsForNode(node.id());
  if (!permissions.length) {
    hideGraphTooltip();
    return;
  }
  tooltip.textContent = [node.data("name"), ...permissions.map(permissionDetails)].join("\n");
  positionGraphTooltip(node.renderedPosition());
}

function scheduleTooltipHide() {
  clearTimeout(tooltipHideTimer);
  tooltipHideTimer = setTimeout(() => {
    hoveredNodeId = undefined;
    hideGraphTooltip();
  }, 100);
}

function positionGraphTooltip(position) {
  const tooltip = document.getElementById("graphTooltip");
  tooltip.style.left = `${Math.min(position.x + 14, cy.width() - 280)}px`;
  tooltip.style.top = `${Math.max(position.y + 14, 12)}px`;
  tooltip.classList.add("visible");
}

function hideGraphTooltip() {
  document.getElementById("graphTooltip").classList.remove("visible");
}

async function fetchGraph() {
  const response = await fetch("/api/graph", { cache: "no-store" });
  if (!response.ok) throw new Error(`Graph request failed: ${response.status}`);
  return response.json();
}

async function loadGraph(showLoading = true) {
  if (showLoading) updateStatus("Loading graph…");
  graphData = await fetchGraph();
  renderGraph();
}

async function regenerateGraph() {
  const button = document.getElementById("regenerateButton");
  button.disabled = true;
  button.textContent = "Regenerating…";
  updateStatus("Collecting LocalStack state and rebuilding graph…");
  try {
    const response = await fetch("/api/regenerate", { method: "POST" });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Graph regeneration failed.");
    graphData = payload.graph;
    renderGraph();
    updateStatus("Graph regenerated from LocalStack state.");
  } catch (error) {
    updateStatus(error.message);
  } finally {
    button.disabled = false;
    button.textContent = "Regenerate from LocalStack";
  }
}

document.getElementById("resetButton").addEventListener("click", () => {
  cy.elements().removeClass("highlighted faded");
  cy.layout({ name: "preset", positions: graphPositions(graphData), fit: true, padding: 90, animate: true }).run();
});
document.getElementById("reloadButton").addEventListener("click", () => loadGraph());
document.getElementById("regenerateButton").addEventListener("click", regenerateGraph);
document.getElementById("sourceSelect").addEventListener("change", (event) => {
  selectedSourceId = event.target.value;
  renderPaths();
});
document.getElementById("zoomInButton").addEventListener("click", () => {
  cy.zoom({ level: cy.zoom() * 1.2, renderedPosition: { x: cy.width() / 2, y: cy.height() / 2 } });
});
document.getElementById("zoomOutButton").addEventListener("click", () => {
  cy.zoom({ level: cy.zoom() / 1.2, renderedPosition: { x: cy.width() / 2, y: cy.height() / 2 } });
});
document.getElementById("highlightButton").addEventListener("click", () => {
  highlightReachability(selectedSourceId);
});

loadGraph().catch((error) => updateStatus(error.message));
