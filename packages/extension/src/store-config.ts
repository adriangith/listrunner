/** Store configuration schema — defines how ListRunner interacts with a store's website. */

export interface StoreConfig {
  id: string;
  name: string;
  logoUrl?: string;
  /** Regions/countries this store operates in. */
  regions: string[];
  /** Base URL of the store's website. */
  baseUrl: string;
  /** URL match patterns for content script activation. */
  matchPatterns: string[];

  search: StoreSearchConfig;
  cart: StoreCartConfig;
  /** Schema version for forward compatibility. */
  schemaVersion: number;
}

export interface StoreSearchConfig {
  /** Strategy for executing a search. */
  method: "url" | "input";
  /** URL template with {query} placeholder. Used when method is "url". */
  urlTemplate?: string;
  /** CSS selector of the search input field. Used when method is "input". */
  inputSelector?: string;
  /** CSS selector of the search submit button. Used when method is "input". */
  submitSelector?: string;
}

export interface StoreCartConfig {
  /** How to detect an add-to-cart action. */
  detectionMethod: "dom-mutation" | "network" | "polling";
  /** CSS selector for the add-to-cart button. */
  addToCartSelector: string;
  /** CSS selector to extract the product name from a product card/tile. */
  productNameSelector: string;
  /** CSS selector to extract the product image from a product card/tile. */
  productImageSelector?: string;
  /** Selector for the cart count badge — used for polling detection. */
  cartCountSelector?: string;
}
