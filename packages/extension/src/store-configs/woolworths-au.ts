import type { StoreConfig } from "../store-config.js";

const woolworthsAU: StoreConfig = {
  id: "woolworths-au",
  name: "Woolworths",
  regions: ["AU"],
  baseUrl: "https://www.woolworths.com.au",
  matchPatterns: ["*://*.woolworths.com.au/*"],
  search: {
    method: "url",
    urlTemplate: "https://www.woolworths.com.au/shop/search/products?searchTerm={query}",
  },
  cart: {
    detectionMethod: "dom-mutation",
    addToCartSelector: "button.cartControls-addCart, button[class*='addToCart']",
    productNameSelector: ".product-title-link, .shelfProductTile-descriptionLink",
    productImageSelector: ".product-image img, .shelfProductTile-image img",
    cartCountSelector: ".cartcount-badge, .cart-count",
  },
  schemaVersion: 1,
};

export default woolworthsAU;
