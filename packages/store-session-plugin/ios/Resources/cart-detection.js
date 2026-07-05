// ListRunner cart-detection content script for coles.com.au (iOS WKWebView).
// Posts {type:"pageLoaded"} at document end and
// {type:"addToCartDetected", productName, productImageUrl} on add-to-cart clicks
// through the storeSessionBridge WKScriptMessageHandler.

(function () {
  var ADD_TO_CART_SELECTOR = "button[data-testid='add-to-cart-button'], button.add-to-cart";
  var PRODUCT_NAME_SELECTOR = ".product__title, .product-title a, h2.product__title";
  var PRODUCT_IMAGE_SELECTOR = ".product__image img, .product-image img";
  var PRODUCT_TILE_SELECTOR = "[class*='product'], [data-testid*='product'], article, .tile, li";

  function postToBridge(message) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.storeSessionBridge) {
      try {
        window.webkit.messageHandlers.storeSessionBridge.postMessage(message);
      } catch (e) {
        // Page may have navigated away mid-click; ignore.
      }
    }
  }

  function extractProductInfo(addButton) {
    var productName = "";
    var productImageUrl = null;

    var productTile = addButton.closest(PRODUCT_TILE_SELECTOR);
    if (productTile) {
      var nameEl = productTile.querySelector(PRODUCT_NAME_SELECTOR);
      if (nameEl) {
        productName = (nameEl.textContent || "").trim();
      }
      var imgEl = productTile.querySelector(PRODUCT_IMAGE_SELECTOR);
      if (imgEl) {
        productImageUrl = imgEl.currentSrc || imgEl.src || imgEl.getAttribute("data-src");
      }
    }

    if (!productName) {
      productName = readPageProductName();
    }
    if (!productImageUrl) {
      productImageUrl = readPageProductImage();
    }

    return {
      productName: productName || "Unknown product",
      productImageUrl: productImageUrl,
    };
  }

  function readPageProductName() {
    var ogTitle = document.querySelector('meta[property="og:title"]');
    if (ogTitle && ogTitle.content && ogTitle.content.trim()) {
      return ogTitle.content.trim();
    }
    var itemProp = document.querySelector("[itemprop='name']");
    if (itemProp && itemProp.textContent && itemProp.textContent.trim()) {
      return itemProp.textContent.trim();
    }
    var h1 = document.querySelector("h1");
    if (h1 && h1.textContent && h1.textContent.trim()) {
      return h1.textContent.trim();
    }
    // Fall through to page title — strip the " | Store" tail.
    return document.title.replace(/\s*[-|–]\s*.+$/, "").trim();
  }

  function readPageProductImage() {
    var ogImg = document.querySelector('meta[property="og:image"]');
    if (ogImg && ogImg.content) {
      return ogImg.content;
    }
    var itemPropImg = document.querySelector("img[itemprop='image']");
    if (itemPropImg) {
      return itemPropImg.currentSrc || itemPropImg.src;
    }
    return null;
  }

  function handleCartClick(event) {
    var target = event.target;
    if (!target || !target.closest) return;
    var addButton = target.closest(ADD_TO_CART_SELECTOR);
    if (!addButton) return;

    var info = extractProductInfo(addButton);
    postToBridge({
      type: "addToCartDetected",
      productName: info.productName,
      productImageUrl: info.productImageUrl,
    });
  }

  // Register capture-phase click listener (survives SPA re-renders).
  document.addEventListener("click", handleCartClick, true);

  // Announce page load.
  postToBridge({ type: "pageLoaded" });
})();