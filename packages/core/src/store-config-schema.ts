/**
 * Schema and runtime validation for StoreConfig records. Lives in core so
 * community configs can be validated from a CI script, a native mobile shell,
 * or the extension at load time without duplicating logic.
 *
 * The shape mirrors packages/extension/src/store-config.ts; keep them in sync.
 */

export interface StoreConfigShape {
  id: string;
  name: string;
  logoUrl?: string;
  regions: string[];
  baseUrl: string;
  matchPatterns: string[];
  search: StoreSearchConfigShape;
  cart: StoreCartConfigShape;
  schemaVersion: number;
}

export interface StoreSearchConfigShape {
  method: "url" | "input";
  urlTemplate?: string;
  inputSelector?: string;
  submitSelector?: string;
}

export interface StoreCartConfigShape {
  detectionMethod: "dom-mutation" | "network" | "polling";
  addToCartSelector: string;
  productNameSelector: string;
  productImageSelector?: string;
  cartCountSelector?: string;
}

export interface ValidationError {
  path: string;
  message: string;
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
}

/** Current schema major version supported by this validator. */
export const CURRENT_SCHEMA_VERSION = 1;

/**
 * Validate a candidate store config. Returns all errors (not just the first)
 * so config authors get one round-trip worth of feedback.
 */
export function validateStoreConfig(input: unknown): ValidationResult {
  const errors: ValidationError[] = [];

  if (!isObject(input)) {
    return {
      valid: false,
      errors: [{ path: "", message: "Config must be an object." }],
    };
  }

  requireString(input, "id", errors, /^[a-z0-9-]+$/);
  requireString(input, "name", errors);
  requireString(input, "baseUrl", errors);

  requireStringArray(input, "regions", errors);
  requireStringArray(input, "matchPatterns", errors);

  if ("logoUrl" in input && input.logoUrl !== undefined) {
    if (typeof input.logoUrl !== "string") {
      errors.push({ path: "logoUrl", message: "logoUrl must be a string." });
    }
  }

  if (typeof input.schemaVersion !== "number") {
    errors.push({
      path: "schemaVersion",
      message: "schemaVersion must be a number.",
    });
  } else if (input.schemaVersion > CURRENT_SCHEMA_VERSION) {
    errors.push({
      path: "schemaVersion",
      message: `schemaVersion ${input.schemaVersion} is newer than supported version ${CURRENT_SCHEMA_VERSION}.`,
    });
  }

  if (!isObject(input.search)) {
    errors.push({ path: "search", message: "search must be an object." });
  } else {
    validateSearch(input.search, errors);
  }

  if (!isObject(input.cart)) {
    errors.push({ path: "cart", message: "cart must be an object." });
  } else {
    validateCart(input.cart, errors);
  }

  return { valid: errors.length === 0, errors };
}

function validateSearch(
  search: Record<string, unknown>,
  errors: ValidationError[],
): void {
  const method = search.method;
  if (method !== "url" && method !== "input") {
    errors.push({
      path: "search.method",
      message: "method must be 'url' or 'input'.",
    });
    return;
  }

  if (method === "url") {
    const tpl = search.urlTemplate;
    if (typeof tpl !== "string" || tpl.length === 0) {
      errors.push({
        path: "search.urlTemplate",
        message: "url search method requires a non-empty urlTemplate.",
      });
    } else if (!tpl.includes("{query}")) {
      errors.push({
        path: "search.urlTemplate",
        message: "urlTemplate must contain a {query} placeholder.",
      });
    }
  }

  if (method === "input") {
    if (typeof search.inputSelector !== "string" || !search.inputSelector) {
      errors.push({
        path: "search.inputSelector",
        message: "input search method requires an inputSelector.",
      });
    }
  }
}

function validateCart(
  cart: Record<string, unknown>,
  errors: ValidationError[],
): void {
  const method = cart.detectionMethod;
  if (method !== "dom-mutation" && method !== "network" && method !== "polling") {
    errors.push({
      path: "cart.detectionMethod",
      message: "detectionMethod must be 'dom-mutation', 'network', or 'polling'.",
    });
  }

  if (
    typeof cart.addToCartSelector !== "string" ||
    !cart.addToCartSelector
  ) {
    errors.push({
      path: "cart.addToCartSelector",
      message: "addToCartSelector is required and must be a non-empty string.",
    });
  }

  if (
    typeof cart.productNameSelector !== "string" ||
    !cart.productNameSelector
  ) {
    errors.push({
      path: "cart.productNameSelector",
      message: "productNameSelector is required and must be a non-empty string.",
    });
  }

  if (
    "productImageSelector" in cart &&
    cart.productImageSelector !== undefined &&
    typeof cart.productImageSelector !== "string"
  ) {
    errors.push({
      path: "cart.productImageSelector",
      message: "productImageSelector must be a string when present.",
    });
  }

  if (
    "cartCountSelector" in cart &&
    cart.cartCountSelector !== undefined &&
    typeof cart.cartCountSelector !== "string"
  ) {
    errors.push({
      path: "cart.cartCountSelector",
      message: "cartCountSelector must be a string when present.",
    });
  }
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function requireString(
  obj: Record<string, unknown>,
  key: string,
  errors: ValidationError[],
  pattern?: RegExp,
): void {
  const value = obj[key];
  if (typeof value !== "string" || value.length === 0) {
    errors.push({ path: key, message: `${key} is required and must be a non-empty string.` });
    return;
  }
  if (pattern && !pattern.test(value)) {
    errors.push({
      path: key,
      message: `${key} '${value}' doesn't match expected pattern ${pattern}.`,
    });
  }
}

function requireStringArray(
  obj: Record<string, unknown>,
  key: string,
  errors: ValidationError[],
): void {
  const value = obj[key];
  if (!Array.isArray(value)) {
    errors.push({ path: key, message: `${key} must be an array.` });
    return;
  }
  if (value.length === 0) {
    errors.push({ path: key, message: `${key} must not be empty.` });
  }
  for (let i = 0; i < value.length; i++) {
    if (typeof value[i] !== "string") {
      errors.push({
        path: `${key}[${i}]`,
        message: `${key}[${i}] must be a string.`,
      });
    }
  }
}
