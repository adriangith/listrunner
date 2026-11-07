# Native store categories

Retailer JSON schema 7 assigns exactly one app-defined `category` to each registered store. The category describes the retailer, not an individual product's aisle. Category grouping is a presentation feature: it does not imply search, retailer availability, automation, host trust, cart detection or Undo support. `automationSchemaVersion` preserves the store's detector-rule version across this metadata-only format migration.

## Schema contract

Schema 7 requires `category` and `automationSchemaVersion` (`2`–`5`). The category is one stable identifier from this vocabulary:

| JSON value | Display label | Meaning |
|---|---|---|
| `grocery` | Grocery | Grocery-focused supermarkets and food retailers |
| `groceryHome` | Groceries & Home | Retailers combining grocery and general home/warehouse ranges |
| `clothingHome` | Clothing & Home | General merchandise retailers focused on clothing and home |
| `homeFurniture` | Home & Furniture | Furniture and home-focused retailers |
| `onlineMarketplace` | Online Marketplace | Broad multi-seller online marketplace |
| `hardwareGarden` | Hardware & Garden | Hardware, building supplies and garden retail |
| `pharmacyBeauty` | Pharmacy & Beauty | Pharmacy, health and beauty retail |
| `electronics` | Electronics | Consumer electronics and appliances |
| `officeSupplies` | Office Supplies | Office, school and business supplies |
| `petSupplies` | Pet Supplies | Pet food and products |
| `automotive` | Automotive | Automotive parts, accessories and care |
| `outdoorCamping` | Outdoor & Camping | Outdoor recreation, camping and fishing |

Schema 6 remains readable using its original, multi-category `categories` array. It has no primary category or ordering semantics: **never choose the first value as the store's category**. For grouping, known registered store IDs use the reviewed mapping below. Schemas 2–5 remain readable with unknown legacy category metadata and use the same reviewed mapping for known registered IDs. Unknown/unmapped records use Uncategorised rather than guessing or disappearing. Legacy wire formats remain unchanged on encoding.

Schema 7 is independent of SwiftData schema V3. `automationSchemaVersion`, capabilities, selectors, host allowlists, stable list/session IDs and availability rules must not change as a result of category migration. Hidden destinations stay hidden.

## Approved assignments

These assignments cover all 33 registered destinations in the planning baseline, including temporarily unavailable stores. Regional destinations retain independent lists and sessions even when they share one category.

| Category | Destinations |
|---|---|
| Grocery | Coles, Woolworths AU, Kroger, Morrisons, New World, Ocado, PAK’nSAVE, Sainsbury’s, Tesco, Waitrose |
| Groceries & Home | Costco AU, Costco US, Walmart, Asda, Target US |
| Clothing & Home | Kmart AU, Target Australia, BIG W, The Warehouse |
| Home & Furniture | IKEA Australia |
| Online Marketplace | Amazon US |
| Hardware & Garden | Bunnings AU, Bunnings NZ |
| Pharmacy & Beauty | Chemist Warehouse, Priceline, Boots, CVS, Walgreens |
| Electronics | JB Hi-Fi |
| Office Supplies | Officeworks |
| Pet Supplies | Petbarn |
| Automotive | Supercheap Auto |
| Outdoor & Camping | BCF |

Grocery and Groceries & Home are intentionally separate groups. Target US is not Target Australia. Pharmacy/beauty is not a prescription-service guarantee; grocery does not imply fresh delivery, Amazon Fresh or Whole Foods; category membership does not certify that ListRunner can search or transact at that retailer.

## Adding or changing a category

1. Confirm a broad retailer type is needed and add a stable raw value and display label in `StoreCategory` in `packages/ios/ListRunner/StoreConfiguration.swift`.
2. Update schema validation, onboarding tooling, `packages/ios/tests/test-store-categories.py`, documentation and every resource assignment.
3. Give every new registered store exactly one reviewed category. Preserve schemas 2–6 and test their decoding; do not infer a schema-6 primary category from array order.
4. Keep category changes metadata-only. Never infer automation, visibility or availability from the category.
5. Run category, configuration, onboarding and bundled-resource tests. Canonical resources are referenced directly; do not create `-v2.json` duplicates.
