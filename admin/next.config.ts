import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: {
    serverActions: {
      // Default ist 1MB — der manuelle Bild-Upload (image-research/actions.ts
      // commitManualImage) schickt das komplette Bild base64-kodiert als
      // Server-Action-Payload (kein multipart/form-data). Base64 bläst die
      // Rohdatei um Faktor ~4/3 auf, die Bildpipeline erlaubt bis zu 15MB
      // (MAX_IMAGE_BYTES in _shared/imagePipeline.ts) — ohne dieses Limit
      // schlug JEDER Upload eines normal großen Fotos (>~750KB) schon vor
      // Erreichen unseres Codes mit "Body exceeded 1 MB limit" fehl.
      bodySizeLimit: "25mb",
    },
  },
};

export default nextConfig;
