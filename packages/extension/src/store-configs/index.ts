import type { StoreConfig } from "../store-config.js";
import woolworthsAU from "./woolworths-au.js";
import colesAU from "./coles-au.js";
import igaAU from "./iga-au.js";

const allConfigs: StoreConfig[] = [woolworthsAU, colesAU, igaAU];

const configMap = new Map(allConfigs.map((c) => [c.id, c]));

export function getStoreConfig(id: string): StoreConfig | undefined {
  return configMap.get(id);
}

export function getAllStoreConfigs(): StoreConfig[] {
  return allConfigs;
}

/** Find which store config matches a given URL. */
export function matchStoreByUrl(url: string): StoreConfig | undefined {
  try {
    const hostname = new URL(url).hostname;
    return allConfigs.find((config) =>
      config.matchPatterns.some((pattern) => {
        const patternHost = pattern
          .replace("*://", "")
          .replace("/*", "")
          .replace("*.", "");
        return hostname.endsWith(patternHost);
      }),
    );
  } catch {
    return undefined;
  }
}
