# Data Sources

This file documents every data source of the Egypt Economic Intelligence Platform: what it is, how it is collected, which rules apply, and what its known limits are. Each source has its own section. Facts were verified on 2026-10-22 unless stated otherwise.

## Static shopping site: Metro Markets (R2)

| Item | Value |
|---|---|
| Site | https://www.metro-markets.com |
| Technique | `requests` + `BeautifulSoup` (server-rendered HTML, no JavaScript needed) |
| Data | Public shelf prices of a fixed basket of 15 staple products |
| Schedule | Daily, 06:00 Africa/Cairo |
| Currency | EGP, VAT inclusive (stated in the site's terms) |

### Why this site

- Pages are server-rendered: names, prices and links are present in the raw HTML.
- Every product page exposes price, currency, availability and a stable numeric item id in `<meta property="product:*">` tags.
- On 2026-10-22 the price matched in three places for all 15 basket products: the category-page card, the product-page price element, and the product meta tag.

### Responsible scraping

- robots.txt (checked 2026-10-22): `User-agent: *` with an empty `Disallow:`, so nothing is disallowed.
- Terms and Conditions (https://www.metro-markets.com/terms-and-conditions, checked 2026-10-22): no clause about robots, crawling, scraping or automated access was found. The terms do not grant explicit permission either, and no written permission has been requested yet.
- Because robots.txt is fully open, the politeness rules come from us:
  - Identify the bot: `User-Agent: EcoPlatformBot/1.0 (student project)`.
  - At least 2 seconds between requests.
  - Production reads only the 15 basket product pages, once per day (about 15 requests).
  - No search, login, cart, checkout or pagination requests in production. Public prices only, no personal data.
  - Stop on 403, 429 or a captcha; never evade a block.
- Only code and small excerpts are published (see `tests/samples/`). Full pages are not republished.

### Page structure used by the parser

| Field | Where it is found |
|---|---|
| Product id | `<meta property="product:retailer_item_id">`, and the number at the end of the URL `/product/<slug>/<id>` |
| Current price | `<meta property="product:price:amount">`, cross-checked against `div.price p.after` |
| Old price (discount) | `div.price p.before` (empty when there is no discount) |
| Currency | `<meta property="product:price:currency">` (EGP) |
| Availability | `<meta property="product:availability">` |
| Name | `og:title`, first `<h5>`, last breadcrumb item |
| Category path | `nav[aria-label="breadcrumb"]` |
| Brand | `product:brand` (unreliable: private-label items show "Private Label", the whole chicken shows "Fresh") |
| Size / unit | Only inside the product name; product pages have no separate unit field |

Planned rule: the price is read from the meta tag; if it differs from the visible price element, the record is a structural validation failure.

### Fixed basket (15 products)

| # | Item (our label) | product_id | Product name on site | Size | Price on 2026-10-22 (EGP) | Notes |
|---|---|---|---|---|---|---|
| 1 | Rice | 4613 | Al Doha Egyptian White Rice | 1 kg | 41.99 | |
| 2 | Sugar | 6896 | Rehana White Sugar | 1 kg | 39.99 | Only white sugar in its category; the other products are powdered or icing sugar |
| 3 | Flour | 6565 | Al Doha Fine Flour | 1 kg | 32.50 | Discount that day (old price 37.50) |
| 4 | Pasta | 4408 | Regina Spaghetti Pasta 1.6mm | 400 g | 25.99 | Discount that day (old price 30.99); the name differs on category cards |
| 5 | Lentils | 27685 | Metro Yellow Lentil | 500 g | 39.99 | |
| 6 | White beans | 27687 | Metro White Beans | 500 g | 64.99 | |
| 7 | Fava beans (canned) | 3513 | Harvest Plain Fava Beans | 400 g | 18.99 | Discount that day (old price 22.45) |
| 8 | Eggs | 9478 | Metro Eggs White | 30 pcs | 148.95 | Egg size is not stated on the page |
| 9 | Tea | 5522 | El-Arosa Dust Tea | 250 g | 53.95 | |
| 10 | Salt | 6563 | Cooks Iodized Table Salt | 700 g | 15.99 | |
| 11 | Milk | 25799 | Labanita Full Cream Milk Tetra | 1 L | 54.00 | |
| 12 | Tuna | 4226 | California Garden Solid Tuna | 185 g | 82.99 | The page description says it is packed in sunflower oil |
| 13 | White cheese | 1671 | Domty Feta Cheese Tetra Pack | 500 g | 54.99 | |
| 14 | Chicken | 33084 | Whole Chicken | 1 kg | 164.99 | Listed as a fixed 1 kg pack |
| 15 | Ghee | 41062 | Alexandria Ghee | 450 g | 291.99 | Tracked instead of cooking oil (see limits) |

This table fixes only which products are tracked. Index weights are decided separately (index view). A product is replaced only by team agreement, because the index compares the same product over time.

### Known limits

1. Branch not selected: the site header shows "Choose Branch" and we do not select one, so prices are the default list. The site's terms say the range and prices may differ by delivery location.
2. Discounts: three basket products (6565, 4408, 3513) had a struck-through old price on the verification day. The current price is the price that is stored. The old price is not stored for now, because `staging.prices_clean` has no column for it; adding one is a shared-schema change that needs the team's agreement (R3).
3. No cooking oil: no bottled edible oil was found in the English catalogue (searches for oil, sunflower and corn, and no oil category in the category tree). The Arabic catalogue was not searched. Ghee is tracked instead. IDSC publishes daily prices of basic commodities including sunflower oil, which could serve as a reference outside the basket (to be decided by the team).
4. Names are not stable across page types (category card vs product page), so identity relies on `product_id` only.
5. Category names on the site are unreliable (for example the "Balady Ghee" category contains cheese-labelled items and "Fresh Milk" contains cream), so our own category labels are used.
6. Descriptions are empty for 7 of the 15 products, and brand metadata is unreliable.
7. Weighed goods: the terms say weighed goods are charged by unit price and the delivered quantity may differ. We record only the listed shelf price.
8. Short verification window: prices were checked within a single day, so stability over time is unknown until daily collection runs.

### Sources evaluated and rejected

| Site | Result | Reason |
|---|---|---|
| Carrefour Egypt | Rejected | Its terms forbid using robots or spiders to navigate the site and restrict copying or storing content beyond personal non-commercial use (read from an archived 2021 copy, because the live terms page is script-rendered). Automated requests from our test machine also received no response (bot protection). |
| Spinneys Egypt | Rejected | Client-rendered app: category pages return no products in the HTML, and the terms page is unreadable without JavaScript. |
| Awlad Ragab | Rejected | Brochure site: offers are published as images, with no online shop prices. |
| Seoudi | Rejected | Corporate website only, no online shop. |
| Gourmet Egypt | Backup | Server-rendered Magento shop; terms (revised 2022-11-15) have no scraping clause. Its robots.txt is ambiguous: the `*` group is open, but a long disallow list (checkout, customer, catalog and others) follows another bot's group, so we would treat it as applying to us. Prices are premium, so it is less representative of basic goods. |
