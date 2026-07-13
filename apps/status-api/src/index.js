import express from "express";

const app = express();
const port = process.env.PORT || 8080;
const startedAt = Date.now();

let requestCount = 0;

app.use((req, res, next) => {
  requestCount += 1;
  next();
});

// CORS: this API is called client-side from the portfolio's CloudFront origin.
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

app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/stats", (req, res) => {
  res.json({
    pod: process.env.POD_NAME || process.env.HOSTNAME || "unknown",
    node: process.env.NODE_NAME || "unknown",
    uptime: formatUptime(Date.now() - startedAt),
    requests: requestCount,
  });
});

app.listen(port, () => {
  console.log(`status-api listening on :${port}`);
});
