import type { StoreConfig } from "../store-config.js";

const igaAU: StoreConfig = {
  id: "iga-au",
  name: "IGA",
  regions: ["AU"],
  baseUrl: "https://www.igashop.com.au",
  matchPatterns: ["*://*.igashop.com.au/*"],
  search: {
    method: "url",
    urlTemplate: "https://www.igashop.com.au/search?query={query}",
  },
  cart: {
    detectionMethod: "dom-mutation",
    addToCartSelector:
      "button[data-testid='add-to-cart'], button[aria-label*='Add to cart' i]",
    productNameSelector:
      "[data-testid='product-title'], .product-title, h3",
    productImageSelector: "img[alt]",
    cartCountSelector:
      "[data-testid='cart-count'], .cart-counter, .cart-badge",
  },
  schemaVersion: 1,
};

export default igaAU;
