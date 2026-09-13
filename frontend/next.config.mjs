/** @type {import('next').NextConfig} */
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));

const nextConfig = {
  reactStrictMode: true,
  // The deploy root is this directory. Without it, a lockfile anywhere above the checkout (a
  // stray home-dir npm install, a monorepo root on the build host) becomes the inferred
  // workspace root and the traced serverless bundle is assembled from there instead.
  outputFileTracingRoot: root,
};

export default nextConfig;
