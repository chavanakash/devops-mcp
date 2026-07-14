// @ts-check
import { defineConfig } from 'astro/config';

import tailwindcss from '@tailwindcss/vite';

// GitHub Pages project-page hosting: chavanakash.github.io/devops-mcp/
// https://astro.build/config
export default defineConfig({
  site: 'https://chavanakash.github.io',
  base: '/devops-mcp',
  vite: {
    plugins: [tailwindcss()]
  }
});
