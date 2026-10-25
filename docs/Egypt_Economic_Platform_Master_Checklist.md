# Egypt Economic Intelligence Platform
### منصة ذكاء الاقتصاد المصري — الـ Architecture + قائمة التنفيذ الكاملة (40 يوم)

> **طريقة الاستخدام:** كل مهمة قدامها مربع `[ ]`. لما المهمة تخلص فعلاً (حسب *Definition of Done* تحت)، علّم عليها `[x]`.
> الملف ده هو **مرجع الفريق الوحيد**: لو في اختلاف بينه وبين أي ملف تاني، ده المعتمد.

---

## 0. مفتاح الأدوار

| الرمز | الدور | المسؤولية الرئيسية |
|---|---|---|
| **R1** | Ingestion Lead | `BaseConnector`، APIs، الملف الرسمي، `raw_store`، تحليل الدولار والذهب |
| **R2** | Scraping & Cleaning Lead | الـ scraper، `cleaning.py`، staging، `records_rejected`، اختبارات الـ parsers |
| **R3** | Warehouse & SQL Lead | ERD، كل الـ DDL، SCD2، UPSERT، مؤشر السلة، Views الـ serving |
| **R4** | Orchestration & Quality Lead | Airflow DAGs، retry/logging، فحوصات الجودة، `ops` |
| **R5** | Platform & DevOps Lead | repo، Docker Compose، FastAPI، Grafana، CI، README |
| **ALL** | كل التيم | |

**أسماء التيم:**

| الدور | الاسم |
|---|---|
| R1 | ahmed el sayed |
| R2 | Ali Ahmed farag |
| R3 | Amr nabil |
| R4 | kareem shehata |
| R5 | Ahmed |

---

# الجزء الأول: الـ Architecture

## 1. الفكرة في جملة

pipeline أوتوماتيك بيجمع بيانات الاقتصاد المصري (أسعار سلع، دولار، ذهب، مؤشرات رسمية) من **4 مصادر بـ 3 تقنيات**، وينضفها، ويخزنها بتاريخها في PostgreSQL، ويطلّع منها مؤشرات وتحليلات تتعرض في **REST API** و **Grafana**.

## 2. النطاق

| أساسي (لازم يخلص) | اختياري (لو الوقت سمح) | خارج النطاق |
|---|---|---|
| 4 مصادر (FX/Gold API، World Bank API، موقع ثابت، ملف رسمي) | مصدر ديناميكي بـ Playwright | MongoDB |
| طبقات raw / staging / dwh / serving / ops | تنبيهات Telegram | Prometheus |
| SCD Type 2 على المنتجات | لوحات Grafana إضافية | Kafka / Spark |
| Airflow مع retry و logging | مصادر إضافية | ML لتوقع الأسعار |
| فحوصات الجودة + `records_rejected` | استخراج جداول من PDF | |
| مؤشر السلة + تحليل الدولار والذهب | | |
| FastAPI + **لوحتين** Grafana (تحليلات + صحة الـ pipeline) | | |
| Docker Compose + GitHub Actions + pytest | | |

> **قاعدة صارمة:** أي إضافة لازم تكون من عمود "اختياري" وبعد ما الأساسي يخلص. **يوم 36 إيقاف كامل لإضافة الميزات.**
> **ترتيب الحذف لو الوقت ضاق:** (1) Playwright والمصادر الإضافية ← (2) Telegram ← (3) لوحات Grafana الإضافية ← (4) تبسيط المؤشر لسلع أقل.
> **ممنوع يتحذف أبداً:** الـ connectors الأساسية، الـ warehouse بـ SCD2، Airflow، فحوصات الجودة، اللوحتين.

## 3. مصادر البيانات

| # | المصدر | التقنية | البيانات | الجدولة | التحدي |
|---|---|---|---|---|---|
| 1 | FX / Gold API | REST + `requests` | الدولار والعملات، الذهب (عيار 24/21/18) | يومي | دعم EGP، شروط الاستخدام، حدود الطلبات |
| 2 | World Bank API | REST + `requests` | مؤشرات اقتصادية لمصر (مثل التضخم) | أسبوعي/شهري | بيانات سنوية، قيم ناقصة |
| 3 | موقع تسوق مصري ثابت | `requests` + `BeautifulSoup` | أسعار 10–20 سلعة أساسية | يومي | تغير شكل الصفحة، robots.txt |
| 4 | ملف إحصائي رسمي | `pandas` (CSV/Excel) | مؤشرات رسمية دورية | أسبوعي/شهري | تنسيق غير ثابت، عناوين عربي |
| 5 *(اختياري)* | موقع JavaScript | Playwright | أسعار إضافية | يومي | ثقيل على الـ RAM |

## 4. مسار البيانات (Data Flow)

```
┌──────────────────────────────────────────────────────────────────────┐
│ المصادر:  FX/Gold API | World Bank API | Static Site | Official File │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Connectors (BaseConnector):  fetch() → parse() → validate() [هيكلي]  │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ raw        البيانات زي ما جت + المصدر + وقت الجمع                    │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ staging    تنظيف وتوحيد (Pandas) + الفحوصات الحرجة [quality_gate]    │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ dwh        Star Schema + SCD Type 2   (أبعاد أولاً ← حقائق ثانياً)   │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ serving    Views فقط (مؤشرات + تحليلات + حالة الـ pipeline)          │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ FastAPI   |   Grafana       (بيقروا من serving فقط بمستخدم reader)   │
└──────────────────────────────────────────────────────────────────────┘

 على الجنب:  Airflow ينسق كل المراحل  ──►  ops.pipeline_runs
                                           ops.records_rejected
                                           ops.quality_results
             (بتتعرض عبر Views في serving)  ──►  لوحة صحة الـ pipeline
             GitHub Actions: lint + pytest على كل push
```

## 5. الطبقات وتنظيم قاعدة البيانات

سيرفر PostgreSQL واحد، فيه **databaseين منفصلتين**:

| Database | المحتوى |
|---|---|
| `eco` | الـ 5 schemas: `raw`, `staging`, `dwh`, `serving`, `ops` |
| `airflow` | بيانات Airflow الداخلية (metadata) |

| Schema | المحتوى | الغرض |
|---|---|---|
| `raw` | `api_responses`, `html_pages`, `files` | حفظ المصدر زي ما هو لإعادة المعالجة |
| `staging` | `prices_clean`, `products`, `fx_gold_clean`, `indicators_clean` | بيانات نظيفة قبل الـ warehouse |
| `dwh` | الأبعاد والحقائق (تحت) | تحليل منظم |
| `serving` | Views | الـ API و Grafana يقروا منها بس |
| `ops` | `pipeline_runs`, `records_rejected`, `quality_results` | المراقبة |

**مستخدمو قاعدة البيانات:** `etl_user` (كتابة على raw/staging/dwh/ops) و `reader` (**SELECT على serving فقط**). الـ API و Grafana بيتصلوا بـ `reader`.

## 6. نموذج البيانات (التسمية المعتمدة)

> قاعدة: `dwh.dim_*` أبعاد، `dwh.fact_*` حقائق، `ops.*` بصيغة الجمع، كله `snake_case` إنجليزي.

| الجدول | النوع | المحتوى |
|---|---|---|
| `dwh.dim_date` | بُعد | التاريخ، الشهر، السنة، الأسبوع |
| `dwh.dim_source` | بُعد | المصدر ونوعه |
| `dwh.dim_product` | بُعد **SCD2** | الاسم، الفئة، الوحدة، `valid_from`, `valid_to`, `is_current` |
| `dwh.dim_currency` | بُعد | عملة أو ذهب (+ عيار) + عمود النوع |
| `dwh.dim_indicator` | بُعد | كود المؤشر، الاسم، الوحدة، الدورية |
| `dwh.fact_price` | حقائق | سعر منتج/يوم/مصدر |
| `dwh.fact_gold_fx` | حقائق | سعر عملة أو ذهب/يوم |
| `dwh.fact_indicator` | حقائق | قيمة مؤشر لفترة (سنة/شهر) |
| `ops.pipeline_runs` | مراقبة | بداية/نهاية/حالة/عدد السجلات لكل تشغيل |
| `ops.records_rejected` | مراقبة | السجل المرفوض + السبب + `stage` (validate/transform) |
| `ops.quality_results` | مراقبة | نتيجة كل فحص |

## 7. تصميم الـ Connectors

```python
class BaseConnector:
    name: str
    def fetch(self):             # يجيب الخام (HTML / JSON / bytes)
        ...
    def parse(self, raw):        # يحوّله لقائمة سجلات (dicts)
        ...
    def validate(self, rows):    # فحص هيكلي → (valid_rows, rejected_rows)
        ...
```

**شكل السجلات الإلزامي الخارج من `parse()`:**

| النوع | الحقول |
|---|---|
| سعر سلعة | `source, product_id, product_name, category, unit, price, currency, observed_at` |
| عملة / ذهب | `source, code, kind (currency\|gold), karat, rate, observed_at` |
| مؤشر | `source, indicator_code, country, period, value` |

**الفرق بين نوعي الرفض:**
- `validate()` في الـ connector = **هيكلي** (حقل ناقص، نوع غلط) ← `stage='validate'`
- التنظيف في `transform` = **منطقي** (سعر ≤ 0، وحدة مجهولة) ← `stage='transform'`

## 8. تنسيق Airflow

**ترتيب المهام في كل DAG:**

```
extract → save_raw → validate → transform → quality_gate → load → post_load_checks
```

- `retries=3`, `retry_delay=5 min`، وأي فشل نهائي يتسجل في `ops.pipeline_runs`.
- `LocalExecutor` لتوفير الـ RAM.
- DAGs الأسعار والدولار والذهب: **يومي، ساعة ثابتة 06:00 بتوقيت Cairo**، و `date_key` من تاريخ Cairo.
- World Bank والملف الرسمي: **أسبوعي/شهري** (نفس القالب، `schedule` مختلف).
- `catchup=False` للـ scraping، وتحميل تاريخي لـ APIs اللي بتدعمه.

## 9. فحوصات الجودة

| الفحص | النوع | الشرط | التوقيت |
|---|---|---|---|
| قيم ناقصة | حرج | لا NULL في السعر/التاريخ/المنتج | قبل التحميل (staging) |
| التكرار | حرج | لا تكرار على (المنتج، المصدر، التاريخ) | قبل التحميل |
| نطاق السعر | حرج | السعر > 0 | قبل التحميل |
| قفزة سعر | تحذيري | تغير > 50% في يوم | بعد التحميل |
| عدد السجلات | تحذيري | نزول > 30% عن آخر تشغيل | بعد التحميل |
| الحداثة | تحذيري | آخر بيانات مش أقدم من المتوقع | بعد التحميل |

الحرج يفشل الـ task **ومبيدخلش الـ warehouse**. التحذيري بيتسجل بس.

## 10. منطق التحميل (SCD2 + الحقائق)

```sql
-- SCD2 خطوة 1: قفل النسخة الحالية لو اتغير attribute
UPDATE dwh.dim_product d
SET valid_to = CURRENT_DATE, is_current = FALSE
FROM staging.products s
WHERE d.product_id = s.product_id AND d.is_current
  AND (d.name IS DISTINCT FROM s.name OR d.category IS DISTINCT FROM s.category);

-- SCD2 خطوة 2: إدخال نسخة جديدة للمنتجات الجديدة أو المتغيرة
INSERT INTO dwh.dim_product (product_id, name, category, unit, valid_from, is_current)
SELECT s.product_id, s.name, s.category, s.unit, CURRENT_DATE, TRUE
FROM staging.products s
LEFT JOIN dwh.dim_product d ON d.product_id = s.product_id AND d.is_current
WHERE d.product_id IS NULL;

-- الحقائق: ربط الـ surrogate keys ثم UPSERT (idempotent)
INSERT INTO dwh.fact_price (product_key, source_key, date_key, price)
SELECT p.product_key, src.source_key, dt.date_key, s.price
FROM staging.prices_clean s
JOIN dwh.dim_product p   ON p.product_id = s.product_id AND p.is_current
JOIN dwh.dim_source  src ON src.source_name = s.source
JOIN dwh.dim_date    dt  ON dt.full_date = s.price_date
ON CONFLICT (product_key, source_key, date_key)
DO UPDATE SET price = EXCLUDED.price;
```

> كل مصدر يتحمّل داخل **transaction واحدة**. الترتيب إجباري: **الأبعاد ثم الحقائق**.

## 11. المؤشرات والتحليلات

```
Index_t = 100 × Σ ( w_i × p_i,t / p_i,0 )        حيث Σ w_i = 1
```

- سلة ثابتة 10–20 سلعة بأوزان محددة مسبقاً، تاريخ الأساس = أول يوم بيانات كاملة، View في SQL.
- الأيام الناقصة: `fill-forward` لأيام قليلة، وبعدها تتعلّم كبيانات ناقصة.
- الدولار والذهب: تغير نسبي + ارتباط مع المؤشر. **الارتباط ≠ سببية** (يتكتب في التوثيق).
- المقارنة بالتضخم الرسمي: **للاتجاه العام فقط** بسبب قصر فترة الجمع.

## 12. التقديم

| Endpoint / لوحة | المحتوى | المصدر |
|---|---|---|
| `GET /prices/latest` | آخر الأسعار | serving |
| `GET /products/{id}/history` | تاريخ سعر منتج | serving |
| `GET /index` | قيم المؤشر | serving |
| `GET /pipeline/status` | حالة آخر تشغيل لكل مصدر | serving (View فوق ops) |
| لوحة التحليلات | المؤشر، الدولار مقابل الذهب، أكتر السلع تغيراً | Grafana |
| لوحة صحة الـ pipeline | نجاح/فشل، مرفوضات، نتائج الجودة | Grafana |

## 13. الأدوات

| المحور | الأداة |
|---|---|
| الجمع | `requests`, `BeautifulSoup`, *(Playwright اختياري)* |
| المعالجة | `pandas` |
| التخزين | PostgreSQL |
| التنسيق | Airflow (LocalExecutor) |
| التشغيل | Docker Compose |
| التقديم | FastAPI, Grafana |
| الجودة | `pytest`, `ruff`, GitHub Actions |
| الإدارة | Git + GitHub (Projects) |

**الـ RAM التقريبي:** postgres ~0.5GB، airflow ~2–3GB، api <0.5GB، grafana ~0.3GB. المجموع أقل بكتير من 16GB.

## 14. العقود المشتركة (ممنوع تتغير من غير موافقة الكل)

**هيكل الـ repo:**

```
egypt-eco-platform/
├── docker-compose.yml
├── .env.example                 # الـ .env الحقيقي في .gitignore
├── sql/   00_databases_roles.sql  10_schemas.sql  20_raw.sql  30_staging.sql
│          40_dwh.sql  50_ops.sql  60_serving.sql
├── src/
│   ├── common/      db.py  raw_store.py  cleaning.py  ops_log.py
│   ├── connectors/  base.py  fx_gold.py  world_bank.py  static_site.py  official_file.py
│   ├── transform/
│   └── quality/
├── dags/
├── api/
├── grafana/
├── tests/samples/               # HTML / JSON / CSV عينات
└── docs/                        # sources.md, architecture, ERD
```

**قواعد الكود:**
1. أي connector في `src/connectors/` ويورّث `BaseConnector`.
2. التنظيف المشترك في `src/common/cleaning.py` فقط (مالكه R2).
3. أي كتابة في raw عبر `raw_store.py`، وأي تسجيل في ops عبر `ops_log.py`.
4. الأسرار في `.env` فقط.
5. أسماء الجداول/الأعمدة حسب القسم 6 فقط.
6. كل parser/تحويل له اختبار pytest بملف عينة.

**قواعد Git:**
- `main` محمي: لا push مباشر، دمج بـ Pull Request + موافقة واحدة على الأقل.
- أسماء الـ branches: `feature/r2-static-scraper` (الدور-المهمة).
- commit بالإنجليزي: `add: fx connector parse()`.
- PR صغير (مهمة واحدة).
- **سلسلة المراجعين:** R1 ↔ R2، R3 ↔ R4، R5 ← R1.

## 15. ضوابط الـ Scraping المسؤول

- قراءة `robots.txt` والشروط قبل الجمع. لو منعت: منجمعش ونبدل المصدر.
- تأخير بين الطلبات، وطلبات قليلة (مرة يومياً).
- `User-Agent` واضح: `EcoPlatformBot/1.0 (student project)`.
- أسعار عامة فقط، بدون بيانات شخصية.
- نشر الكود وعينة صغيرة فقط، مش البيانات الخام الكاملة.
- ذكر المصادر في التوثيق.
- المشروع للتحليل والعرض، مش نصيحة استثمارية ولا توقع أسعار.

---

# الجزء الثاني: نظام العمل

## 16. Definition of Done (متى المهمة تتعلّم `[x]`)

المهمة تخلص لما **كل** ده يتحقق:

- الكود شغال **داخل Docker** (مش على جهازك بس).
- فيه اختبار لو فيها parser أو تحويل.
- الـ PR اتراجع واندمج في `main`.
- جملتين توثيق اتضافوا في `docs/`.

## 17. الاجتماعات والمتابعة

| الاجتماع | التوقيت | المدة | الشكل |
|---|---|---|---|
| Daily | كل يوم | 10 دقايق | عملت إيه امبارح؟ هعمل إيه النهارده؟ في حاجة معطلاني؟ |
| Weekly Demo | مرة في الأسبوع | 30 دقيقة | كل واحد يشغّل اللي عمله + مراجعة التأخير |

- لوحة مهام (GitHub Projects): `Backlog → Doing → Review → Done`، **ومعاك مهمتين Doing كحد أقصى**.
- لو واقف أكتر من **ساعتين**: اسأل التيم، متفضلش لوحدك.
- كل أسبوع: جرّب `docker compose up -d` من repo نظيف.
- لو حد اتأخر: اللي بعده يشتغل على **mock** ويبدّله بالحقيقي لما يجهز.
- لو دور مش مناسب لحد: بدّلوا خلال **أول أسبوع**.

---

# الجزء الثالث: قائمة التنفيذ الكاملة

> **الصيغة:** `[ ]` **رقم المهمة** `(الدور)` وصف المهمة — *المخرج*

---

## المرحلة 1: التجهيز والتصميم (أيام 1–4)

### R5: البيئة
- [x] **1.1a** `(R2)` إنشاء GitHub repo للمشروع (تم)
- [x] **1.1b** `(R2)` إضافة الـ 4 أعضاء كـ Collaborators (Settings ثم Collaborators) وإرسال رابط الـ repo للتيم
- [x] **1.1c** `(R5)` إضافة هيكل الفولدرات (قسم 14) + `.gitignore` + `.env.example`، ورفع ملف الـ md في `docs/`
- [x] **1.2** `(R5)` كتابة `docker-compose.yml` لـ PostgreSQL (database `eco` + database `airflow`) مع volume
- [ ] **1.3** `(R5)` تشغيل البيئة عند **الـ 5 أعضاء** (كل واحد clone + `docker compose up -d` بنجاح)
- [ ] **1.4** `(R5)` تفعيل حماية `main` (PR + موافقة واحدة)
- [ ] **1.5** `(R5)` إنشاء GitHub Project بالأعمدة (Backlog / Doing / Review / Done) وإضافة كل مهام الملف ده
- [ ] **1.6** `(R5)` إعداد Airflow في Compose (بالتنسيق مع R4)

### R3: تصميم الـ Warehouse
- [ ] **1.7** `(R3)` رسم ERD للـ dwh (الأبعاد والحقائق في قسم 6) → `docs/erd`
- [ ] **1.8** `(R3)` كتابة DDL لكل الـ schemas: `raw`, `staging`, `dwh`, `ops`, `serving` (ملفات `sql/*.sql`)
- [ ] **1.9** `(R3)` إنشاء المستخدمين `etl_user` و `reader` (SELECT على serving فقط)
- [ ] **1.10** `(R3)` تنفيذ الـ DDL على Postgres، وكل الأدوار تراجع الأسماء

### R1: المصادر (APIs والملف الرسمي)
- [ ] **1.11** `(R1)` قراءة شروط استخدام FX/Gold API وحدود الطلبات
- [ ] **1.12** `(R1)` تأكيد إن FX/Gold API بيدعم **EGP** والذهب بالعيارات (لو لا: اختيار بديل **الآن**)
- [ ] **1.13** `(R1)` تجربة World Bank API (مؤشر التضخم لمصر) وحفظ عينة JSON
- [ ] **1.14** `(R1)` حفظ عينة JSON من FX/Gold API في `tests/samples/`
- [ ] **1.15** `(R1)` كتابة `BaseConnector` في `src/connectors/base.py` والاتفاق عليه مع التيم
- [ ] **1.16** `(R1)` تحديد الملف الرسمي (إيه هو؟ من أنهي جهة؟ شروط استخدامه؟)
- [ ] **1.17** `(R1)` توثيق المصادر في `docs/sources.md`

### R2: الـ Scraping
- [ ] **1.18** `(R2)` اختيار الموقع الثابت (10–20 سلعة أساسية)
- [ ] **1.19** `(R2)` قراءة `robots.txt` وشروط الاستخدام (لو منعت: موقع بديل)
- [ ] **1.20** `(R2)` حفظ صفحة قائمة + صفحة منتج HTML كعينات في `tests/samples/`
- [ ] **1.21** `(R2)` تحديد `product_id` ثابت (SKU أو slug الرابط) **مش من الاسم**
- [ ] **1.22** `(R2)` توثيق الموقع في `docs/sources.md`

### R4: التعلم
- [ ] **1.23** `(R4)` تعلم أساسيات Airflow (DAG, task, schedule, retry)
- [x] **1.24** `(R4)` DAG تجريبي بسيط بيظهر في الـ UI

### ✅ نقطة تحقق يوم 4
- [ ] **CP-4** البيئة شغالة عند الـ 5، المصادر الأربعة (أو بدائلها) موثقة، الـ ERD والـ DDL معتمدين، شكل `BaseConnector` متفق عليه

---

## المرحلة 2: الـ APIs و Airflow (أيام 5–10)

### R1
- [ ] **2.1** `(R1)` `raw_store.py` (كتابة أي خام في `raw.*` مع المصدر ووقت الجمع)
- [ ] **2.2** `(R1)` connector الدولار والذهب (`fx_gold.py`): `fetch` مع timeout + `raise_for_status` + فحص شكل الـ JSON
- [ ] **2.3** `(R1)` `parse()` + `validate()` لـ FX/Gold
- [ ] **2.4** `(R1)` connector World Bank (`world_bank.py`) كامل
- [ ] **2.5** `(R1)` اختبارات pytest لـ parsers الـ APIs بملفات العينة

### R2
- [ ] **2.6** `(R2)` scraper **raw-only**: `fetch` + حفظ HTML خام في `raw.html_pages` (بدون parsing)
- [ ] **2.7** `(R2)` `User-Agent` واضح + تأخير 2 ثانية بين الطلبات
- [ ] **2.8** `(R2)` تسليم الـ scraper raw-only قبل **يوم 9** (عشان يتجدول يوم 10)

### R3
- [ ] **2.9** `(R3)` DDL كامل ومحدّث بعد ملاحظات التيم
- [ ] **2.10** `(R3)` إنشاء بيانات عينة (CSV/INSERT) لتجربة التحميل
- [ ] **2.11** `(R3)` تدريب على SCD2 على بيانات العينة (تغيير فئة منتج وتتأكد إن النسخة القديمة اتقفلت)

### R4
- [ ] **2.12** `(R4)` `ops_log.py` (تسجيل بداية/نهاية/حالة في `ops.pipeline_runs`)
- [ ] **2.13** `(R4)` قالب DAG (extract → save_raw → validate → transform → quality_gate → load → post_load_checks)
- [ ] **2.14** `(R4)` `retries=3` + `retry_delay=5min` + logging
- [ ] **2.15** `(R4)` ضبط الجدولة: 06:00 Cairo يومي، وأسبوعي/شهري للمصادر الدورية
- [ ] **2.16** `(R4)` تسليم قالب الـ DAG قبل **يوم 8**
- [ ] **2.17** `(R4)` تشغيل DAGs الـ APIs + الـ scraper raw-only **بالجدولة الفعلية يوم 10**

### R5
- [ ] **2.18** `(R5)` Airflow شغال في Compose بـ `LocalExecutor`
- [ ] **2.19** `(R5)` FastAPI skeleton (`/health` + endpoints فاضية)
- [ ] **2.20** `(R5)` CI أولي: `ruff` + `pytest` على كل push
- [ ] **2.21** `(R5)` قياس استهلاك الـ RAM الفعلي للخدمات

### ✅ نقطة تحقق يوم 10
- [ ] **CP-10** الجدولة شغالة وبيانات بتتجمع يومياً (raw) من الـ APIs والـ scraper

---

## المرحلة 3: الـ Scraping والتنظيف (أيام 11–16)

### R2
- [ ] **3.1** `(R2)` `parse()` للـ scraper بـ CSS selectors (اسم، سعر، وحدة، فئة، `product_id`)
- [ ] **3.2** `(R2)` `validate()` الهيكلي للـ scraper
- [ ] **3.3** `(R2)` `cleaning.py`: تحويل الأرقام العربية-الهندية وإزالة رموز العملة والفواصل → numeric
- [ ] **3.4** `(R2)` `cleaning.py`: تطبيع النص العربي (إزالة التشكيل والتطويل، أ إ آ ← ا، ى ← ي)
- [ ] **3.5** `(R2)` `cleaning.py`: توحيد الوحدات (كجم/جم/لتر) وحساب سعر الوحدة
- [ ] **3.6** `(R2)` `cleaning.py`: توحيد التاريخ بتوقيت `Africa/Cairo`
- [ ] **3.7** `(R2)` إزالة المكرر على (المنتج، المصدر، التاريخ)
- [ ] **3.8** `(R2)` تسجيل المرفوضات في `ops.records_rejected` مع `stage` والسبب
- [ ] **3.9** `(R2)` بناء جداول staging (`prices_clean`, `products`) والتحويل ليها من raw
- [ ] **3.10** `(R2)` اختبارات pytest للـ parser والتنظيف على صفحات HTML العينة (بدون إنترنت)
- [ ] **3.11** `(R2)` **تسليم عينة staging نظيفة (CSV) لـ R3 قبل يوم 12**

### R1
- [ ] **3.12** `(R1)` مساعدة R2 في اختبارات الـ parsers
- [ ] **3.13** `(R1)` تحميل تاريخي للدولار والذهب والمؤشرات (للـ APIs اللي بتدعمه)

### R3
- [ ] **3.14** `(R3)` تصميم SQL تحميل الـ dwh على عينة staging (الأبعاد ثم الحقائق)
- [ ] **3.15** `(R3)` Views **mock** في `serving` لـ R5 **قبل يوم 12**

### R4
- [ ] **3.16** `(R4)` دمج الـ scraper الكامل (parse + transform) في الـ DAG

### R5
- [ ] **3.17** `(R5)` بناء endpoints الـ API على Views الـ mock
- [ ] **3.18** `(R5)` Grafana skeleton متصل بمستخدم `reader`

### ✅ نقطة تحقق يوم 16
- [ ] **CP-16** الـ scraper شغال ومجدول بالـ parsing والتنظيف، و staging بتتبني تلقائياً

---

## المرحلة 4: الـ Warehouse (أيام 17–22)

### R3
- [ ] **4.1** `(R3)` تحميل `dim_date` و `dim_source` و `dim_currency` و `dim_indicator`
- [ ] **4.2** `(R3)` SCD2 على `dim_product` بخطوتين (قفل ثم إدخال)، مع تطبيع الاسم قبل المقارنة
- [ ] **4.3** `(R3)` تحميل `fact_price` بـ UPSERT مع ربط الـ surrogate keys
- [ ] **4.4** `(R3)` تحميل `fact_gold_fx` و `fact_indicator`
- [ ] **4.5** `(R3)` `indexes` على `date_key` و `product_key`
- [ ] **4.6** `(R3)` اختبار **idempotency**: تشغيل التحميل مرتين = نفس الأرقام
- [ ] **4.7** `(R3)` اختبار SCD2: تغيير فئة منتج ينتج نسختين صح
- [ ] **4.8** `(R3)` كل مصدر داخل **transaction واحدة**

### R1
- [ ] **4.9** `(R1)` staging للـ APIs (`fx_gold_clean`, `indicators_clean`) + تحويلها من raw
- [ ] **4.10** `(R1)` معالجة القيم الناقصة في World Bank

### R2
- [ ] **4.11** `(R2)` تحسين التنظيف حسب الأخطاء الحقيقية من الأيام اللي فاتت (مراجعة `records_rejected`)

### R4
- [ ] **4.12** `(R4)` task الـ `load` في الـ DAG بيشغل SQL الـ dwh
- [ ] **4.13** `(R4)` `quality_gate` (الفحوصات الحرجة قبل التحميل)

### R5
- [ ] **4.14** `(R5)` اختبارات pytest للتحويلات
- [ ] **4.15** `(R5)` مراجعة PRs التيم، والتأكد إن CI أخضر

### ✅ نقطة تحقق يوم 22
- [ ] **CP-22** الـ warehouse جاهز ومتحمّل أوتوماتيك من الـ DAGs

---

## المرحلة 5: الجودة والملف الرسمي (أيام 23–27)

### R1
- [ ] **5.1** `(R1)` connector الملف الرسمي: تحميل + حفظ الخام في `raw.files` + قراءة بأعمدة محددة مسبقاً
- [ ] **5.2** `(R1)` معالجة العناوين العربي وتنسيق الملف + اختبار بعينة
- [ ] **5.3** `(R1)` إضافة الملف الرسمي في DAG (أسبوعي/شهري)

### R4
- [ ] **5.4** `(R4)` الفحوصات الحرجة: NULL، تكرار، نطاق السعر
- [ ] **5.5** `(R4)` الفحوصات التحذيرية: قفزة سعر، عدد السجلات، الحداثة
- [ ] **5.6** `(R4)` تسجيل كل النتائج في `ops.quality_results`
- [ ] **5.7** `(R4)` `post_load_checks` بعد التحميل
- [ ] **5.8** `(R4)` تأكيد إن أي فشل نهائي بيتسجل في `ops.pipeline_runs`

### R3
- [ ] **5.9** `(R3)` Views أولية للمؤشر
- [ ] **5.10** `(R3)` Views فوق ops (`serving.v_pipeline_status`, `serving.v_rejected_summary`) لـ R5

### R5
- [ ] **5.11** `(R5)` لوحة Grafana **صحة الـ pipeline** (نجاح/فشل، مرفوضات، نتائج جودة)

### R2
- [ ] **5.12** `(R2)` *(اختياري)* مصدر Playwright لو الوقت سمح، وإلا مساعدة التيم

### ✅ نقطة تحقق يوم 27
- [ ] **CP-27** الجودة والمراقبة شغالين، وكل الـ 4 connectors الأساسية في DAGs

---

## المرحلة 6: المؤشرات والـ API (أيام 28–32)

### R3
- [ ] **6.1** `(R3)` مؤشر السلة كـ View (أوزان محددة، تاريخ أساس، `SUM(w)=1`)
- [ ] **6.2** `(R3)` `fill-forward` محدود للأيام الناقصة
- [ ] **6.3** `(R3)` Views الـ serving النهائية (آخر الأسعار، تاريخ منتج، المؤشر، حالة الـ pipeline)

### R1
- [ ] **6.4** `(R1)` Views تحليل الدولار والذهب (تغير نسبي + ارتباط مع المؤشر)
- [ ] **6.5** `(R1)` توثيق إن الارتباط ≠ سببية

### R2
- [ ] **6.6** `(R2)` View أكتر السلع تغيراً (Window Function `LAG`)

### R4
- [ ] **6.7** `(R4)` مراقبة الـ DAGs وتثبيتها (مفيش تشغيل فاشل بدون سبب مفهوم)

### R5
- [ ] **6.8** `(R5)` FastAPI كامل: `/prices/latest`, `/products/{id}/history`, `/index`, `/pipeline/status`
- [ ] **6.9** `(R5)` كل الـ API بيقرأ من `serving` فقط عبر `reader`
- [ ] **6.10** `(R5)` اختبار الـ endpoints

### ✅ نقطة تحقق يوم 32
- [ ] **CP-32** الـ API والمؤشر شغالين

---

## المرحلة 7: العرض والتشغيل والـ CI (أيام 33–36)

- [ ] **7.1** `(R5)` لوحة Grafana **التحليلات** (المؤشر، الدولار مقابل الذهب، أكتر السلع تغيراً)
- [ ] **7.2** `(R5)` تثبيت Docker Compose (أمر واحد يشغّل كل حاجة)
- [ ] **7.3** `(R5)` GitHub Actions: `ruff` + `pytest` أخضر على `main`
- [ ] **7.4** `(R3)` تحسين أداء الـ SQL (`EXPLAIN` على أبطأ الـ Views)
- [ ] **7.5** `(R4)` ثبات الـ pipeline: مراجعة سجل التشغيل والـ retries
- [ ] **7.6** `(R1)` استكمال الاختبارات وإصلاح الأخطاء
- [ ] **7.7** `(R2)` استكمال الاختبارات وإصلاح الأخطاء
- [ ] **7.8** `(ALL)` تجهيز **بيانات احتياطية/نسخة raw** للعرض لو مصدر وقع
- [ ] **7.9** `(ALL)` مراجعة قاعدة الـ Scraping المسؤول (قسم 15)
- [ ] **7.10** `(ALL)` 🛑 **يوم 36: إيقاف إضافة الميزات نهائياً**

### ✅ نقطة تحقق يوم 36
- [ ] **CP-36** نظام متكامل ومستقر، ومفيش ميزات جديدة

---

## المرحلة 8: التوثيق والتجهيز النهائي (أيام 37–40)

- [ ] **8.1** `(R1)` توثيق جزء الـ APIs والملف الرسمي في `docs/`
- [ ] **8.2** `(R2)` توثيق الـ scraper والتنظيف في `docs/`
- [ ] **8.3** `(R3)` توثيق الـ warehouse + ERD النهائي في `docs/`
- [ ] **8.4** `(R4)` توثيق Airflow والجودة في `docs/`
- [ ] **8.5** `(R5)` تجميع الـ **README** (فكرة، تشغيل، مصادر، حدود التحليل)
- [ ] **8.6** `(R5)` رسم الـ architecture diagram النهائي
- [ ] **8.7** `(R5)` لقطات شاشة للـ dashboards والـ Airflow
- [ ] **8.8** `(R5)` تسجيل فيديو demo
- [ ] **8.9** `(ALL)` **تجربة تشغيل من الصفر** على جهاز نظيف: `git clone` ثم `docker compose up -d` ثم بيانات ظاهرة
- [ ] **8.10** `(ALL)` ذكر المصادر وحدود التحليل (فترة الجمع القصيرة، الارتباط ≠ سببية) في README
- [ ] **8.11** `(ALL)` بروفة العرض: كل واحد يشرح جزءه ويعرف جزء غيره
- [ ] **8.12** `(ALL)` رفع نسخة نهائية على GitHub (بدون `.env` ولا بيانات خام كاملة)

### ✅ نقطة تحقق يوم 40
- [ ] **CP-40** التسليم

---

# الجزء الرابع: ملاحق

## 18. جدول التسليمات بين الأدوار

| المُسلِّم | المُستلِم | المطلوب | آخر موعد |
|---|---|---|---|
| R5 | الكل | repo + Docker + PostgreSQL شغالين | يوم 3 |
| R1 | R3, R2 | شكل `BaseConnector` + عينات JSON | يوم 4 |
| R3 | الكل | ERD + DDL أولي | يوم 4 |
| R4 | R1, R2 | قالب DAG + `ops_log.py` | يوم 8 |
| R1, R2 | R4 | connectors (APIs + scraper raw-only) | يوم 9 |
| R2 | R3 | عينة staging نظيفة | يوم 12 |
| R3 | R5 | Views mock في serving | يوم 12 |
| R2 | R3, R4 | staging الحقيقية بالتنظيف | يوم 16 |
| R3 | R4 | dwh + SCD2 + UPSERT جاهزين | يوم 22 |
| R1 | R4 | connector الملف الرسمي | يوم 27 |
| R3 | R5 | Views serving النهائية | يوم 28 |

## 19. نقاط التحقق الرئيسية

| اليوم | نقطة التحقق | المسؤول |
|---|---|---|
| 4 | بيئة + مصادر + ERD | R5 + R3 |
| 10 | الجدولة شغالة وبيانات بتتجمع | R4 |
| 16 | الـ scraper والتنظيف شغالين | R2 |
| 22 | الـ warehouse جاهز ومتحمّل أوتوماتيك | R3 |
| 27 | الجودة والمراقبة شغالين | R4 |
| 32 | الـ API والمؤشر شغالين | R5 + R3 |
| 36 | إيقاف الميزات | الكل |
| 40 | التسليم | الكل |

## 20. المخاطر والحلول

| الخطر | الحل |
|---|---|
| الموقع بيغير شكل الصفحة | اختبارات على HTML محفوظ + فحص نزول عدد السجلات |
| الموقع بيمنع الـ bots | تبديل المصدر (التصميم بـ connectors بيسهّل ده) |
| فترة جمع قصيرة (~30 يوم) | بدء الجدولة يوم 10 (raw-only) + بيانات تاريخية للـ APIs + توضيح الحدود |
| عطل مصدر وقت العرض | نسخة raw + بيانات احتياطية |
| حدود الـ APIs أو تغير شكلها | فحص الـ schema + retry + تسجيل الفشل |
| ضغط الـ RAM | `LocalExecutor` + Playwright عند الحاجة بس |
| ضيق الوقت | الحذف بالترتيب (قسم 2) + إيقاف الميزات يوم 36 |
| تأخر عضو أو دور مش مناسب | عقود + mock + تبديل أدوار خلال أول أسبوع |
| تعارض Git | ملفات لكل دور + PRs صغيرة + `main` محمي |

## 21. التعارضات اللي اتصلحت من الـ PDF الأصلي (للتوثيق)

| # | التعارض | الحل المعتمد |
|---|---|---|
| 1 | serving فقط vs قراءة ops | Views في serving فوق ops + مستخدم `reader` |
| 2 | أسماء الجداول مختلفة | تسمية موحدة (قسم 6) |
| 3 | SQL الحقائق ناقص (surrogate keys) | JOIN مع الأبعاد (قسم 10) |
| 4 | الجدولة يوم 10 vs scraper يوم 16 | scraper raw-only يوم 9 |
| 5 | SCD2 محتاج `product_id` ثابت | SKU/slug + تطبيع الاسم |
| 6 | مفيش بُعد للمؤشرات | `dim_indicator` |
| 7 | قاعدة Airflow | database منفصلة `airflow` |
| 8 | الفحوصات الحرجة بعد التحميل | `quality_gate` قبل التحميل |
| 9 | غموض validate vs transform | هيكلي vs منطقي + عمود `stage` |
| 10 | تواريخ التشغيل | 06:00 Cairo ثابت + `date_key` من Cairo |
| 11 | مصادر دورية vs DAG يومي | `schedule` مختلف لكل مصدر |
| 12 | "أي dashboard" غير محدد | لوحتين إلزاميتين |

---

## 22. شريط التقدم (حدّثه كل أسبوع)

| المرحلة | الأيام | عدد المهام | المنجز |
|---|---|---|---|
| 1. تجهيز وتصميم | 1–4 | 24 + CP | ___ |
| 2. APIs و Airflow | 5–10 | 21 + CP | ___ |
| 3. Scraping وتنظيف | 11–16 | 18 + CP | ___ |
| 4. Warehouse | 17–22 | 15 + CP | ___ |
| 5. جودة وملف رسمي | 23–27 | 12 + CP | ___ |
| 6. مؤشرات و API | 28–32 | 10 + CP | ___ |
| 7. عرض وتشغيل | 33–36 | 10 + CP | ___ |
| 8. توثيق وتسليم | 37–40 | 12 + CP | ___ |

> **تذكير:** الأسعار مبتتجمعش بأثر رجعي. كل يوم تأخير في بدء الجدولة = يوم أقل من التاريخ. **الجدولة تبدأ يوم 10 مهما حصل.**
