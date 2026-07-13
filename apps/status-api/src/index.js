import express from "express";

const app = express();
const port = process.env.PORT || 8080;
const startedAt = Date.now();

let requestCount = 0;

app.use((req, res, next) => {
  requestCount += 1;
  next();
});

// CORS: harmless to leave on even though /api/* is same-origin once proxied
// through CloudFront — only matters for direct http://<node-ip>:30080 access.
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  next();
});

function formatUptime(ms) {
  const totalSeconds = Math.floor(ms / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return `${hours}h ${minutes}m ${seconds}s`;
}

function health(req, res) {
  res.json({ status: "ok" });
}

function stats(req, res) {
  res.json({
    pod: process.env.POD_NAME || process.env.HOSTNAME || "unknown",
    node: process.env.NODE_NAME || "unknown",
    uptime: formatUptime(Date.now() - startedAt),
    requests: requestCount,
  });
}

// Plain paths for direct NodePort access (debugging, runbooks); /api/* is what
// the portfolio site calls, proxied through CloudFront so the browser only
// ever talks to an HTTPS origin — status-api itself has no TLS.
app.get("/health", health);
app.get("/stats", stats);
app.get("/api/health", health);
app.get("/api/stats", stats);

app.listen(port, () => {
  console.log(`status-api listening on :${port}`);
});
