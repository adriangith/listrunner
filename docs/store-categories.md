# Native store categories

The native iOS retailer-definition JSON format uses **schema version 6** to add app-defined retailer categories. Schema 5 was already used by IKEA's verified-cart-snapshot engine when this branch was integrated, so the category format was advanced to avoid a collision. A category describes a broad kind of retailer, not a product department guarantee or a ListRunner automation capability.

## Contract

Every schema-6 definition has a non-empty `categories` array of distinct values from this fixed vocabulary. It also carries `automationSchemaVersion` (`2`, `3`, `4` or `5`): the automation-rule version the retailer used before its data format was upgraded. This explicit compatibility marker keeps a category-only migration from changing retailer-specific detection behavior. New schema-6 definitions must choose a reviewed existing automation-rule version; a new rule set requires a deliberate rule-version change, not a category-format bump.

| JSON value | Meaning |
|---|---|
| `grocery` | Supermarkets and food retailers |
| `departmentStore` | General merchandise and department stores |
| `warehouseClub` | Membership/warehouse club retailers |
| `onlineMarketplace` | Broad multi-seller online marketplace |
| `hardwareGarden` | Hardware, building supplies and garden retail |
| `pharmacyBeauty` | Pharmacy, health and beauty retail |
| `electronics` | Consumer electronics and appliances |
| `officeSupplies` | Office, school and business supplies |
| `petSupplies` | Pet food and products |
| `automotive` | Automotive parts, accessories and care |
| `outdoorCamping` | Outdoor recreation, camping and fishing |

Values are stable identifiers. Unknown values, wrong casing, whitespace, duplicates, non-string values, an empty array or a missing schema-6 field make the definition invalid. The array order has no runtime meaning; bundled arrays use the vocabulary order for consistent diffs. Categories are currently metadata only: they do not affect search, visibility, ordering, host trust, cart detection, Undo, retailer availability or certification.

Definitions using schema versions 2–5 remain supported with their original field set. Their category value is unknown (represented in memory by an empty array), not inferred, and their automation-rule version is the same as their schema version. A categories or `automationSchemaVersion` field on a legacy-version definition is rejected. Schema 6 preserves each retailer's prior search/cart behavior using its explicit automation-rule version; it does not widen any native capability ceiling. SwiftData database schema V3 is unrelated and unchanged.

## Current retailer classification

This broad editorial classification includes meaningful secondary ranges where appropriate. It is not an exhaustive department inventory, and retail ranges vary by market and over time.

| Destination | Categories |
|---|---|
| Amazon US | Grocery; online marketplace; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; automotive; outdoor & camping |
| Asda | Grocery; department store; pharmacy & beauty; electronics; office supplies; pet supplies |
| BCF | Hardware & garden; electronics; automotive; outdoor & camping |
| BIG W | Department store; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; outdoor & camping |
| Boots | Pharmacy & beauty |
| Bunnings AU | Hardware & garden; electronics; pet supplies; automotive; outdoor & camping |
| Bunnings NZ | Hardware & garden; electronics; pet supplies; automotive; outdoor & camping |
| Chemist Warehouse | Pharmacy & beauty |
| Coles | Grocery; pharmacy & beauty; pet supplies |
| Costco AU | Grocery; warehouse club; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; automotive; outdoor & camping |
| Costco US | Grocery; warehouse club; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; automotive; outdoor & camping |
| CVS | Grocery; pharmacy & beauty |
| IKEA AU | Department store; hardware & garden; electronics; office supplies |
| JB Hi-Fi | Electronics |
| Kmart AU | Department store; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; outdoor & camping |
| Kroger | Grocery; pharmacy & beauty; pet supplies |
| Morrisons | Grocery; pharmacy & beauty; electronics; office supplies; pet supplies |
| New World | Grocery; pharmacy & beauty; pet supplies |
| Ocado | Grocery; pharmacy & beauty; pet supplies |
| Officeworks | Electronics; office supplies |
| PAK’nSAVE | Grocery; pharmacy & beauty; pet supplies |
| Petbarn | Pet supplies |
| Priceline | Pharmacy & beauty |
| Sainsbury’s | Grocery; pharmacy & beauty; electronics; office supplies; pet supplies |
| Supercheap Auto | Electronics; automotive; outdoor & camping |
| Target US | Grocery; department store; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; automotive; outdoor & camping |
| Target Australia | Department store; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; outdoor & camping |
| Tesco | Grocery; pharmacy & beauty; electronics; office supplies; pet supplies |
| The Warehouse | Department store; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; outdoor & camping |
| Waitrose | Grocery; pharmacy & beauty; pet supplies |
| Walgreens | Grocery; pharmacy & beauty |
| Walmart | Grocery; department store; hardware & garden; pharmacy & beauty; electronics; office supplies; pet supplies; automotive; outdoor & camping |
| Woolworths AU | Grocery; pharmacy & beauty; pet supplies |

Classification caveats: pharmacy/beauty means common health and personal-care ranges, not a prescription-service guarantee; grocery does not imply fresh delivery or Amazon Fresh/Whole Foods; online marketplace is not synonymous with having a website. Store categories do not certify that ListRunner can search or transact in any listed department. Regional destinations have independent JSON metadata even when their current categories match.

## Adding or changing a category

1. Confirm the value is a broad retailer type that cannot be represented by an existing stable value. Add it to `StoreCategory` in `packages/ios/ListRunner/StoreConfiguration.swift`; do not reuse or rename a shipped raw value.
2. Document its exact meaning and update `docs/store-categories.md` and the assignment contract in `packages/ios/tests/test-store-categories.py`.
3. Classify every registered native destination explicitly. The test requires an exhaustive mapping and a schema-6 categories array for every retailer JSON.
4. Keep the change metadata-only unless a separate, reviewed feature changes category consumers. Do not infer automation or store availability from category membership.

To add a retailer, register its trusted native `StoreID`, add its canonical resource file and Xcode resource reference, classify it explicitly, and run the category, configuration and bundled-resource tests. Do not create duplicate `-v2.json` resources.
