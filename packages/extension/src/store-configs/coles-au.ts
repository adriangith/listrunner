import type { StoreConfig } from "../store-config.js";

const colesAU: StoreConfig = {
  id: "coles-au",
  name: "Coles",
  regions: ["AU"],
  baseUrl: "https://www.coles.com.au",
  matchPatterns: ["*://*.coles.com.au/*"],
  search: {
    method: "url",
    urlTemplate: "https://www.coles.com.au/search?q={query}",
  },
  cart: {
    detectionMethod: "dom-mutation",
    addToCartSelector: "button[data-testid='add-to-cart-button'], button.add-to-cart",
    productNameSelector: ".product__title, .product-title a, h2.product__title",
    productImageSelector: ".product__image img, .product-image img",
    cartCountSelector: ".trolley-count, .cart-badge-count",
  },
  schemaVersion: 1,
};

export default colesAU;
