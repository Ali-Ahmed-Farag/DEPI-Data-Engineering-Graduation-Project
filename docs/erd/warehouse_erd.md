\# Egypt Economic Intelligence Platform



\## Data Warehouse ERD



```mermaid

erDiagram

&#x20;   DIM\_DATE ||--o{ FACT\_PRICE : "has"

&#x20;   DIM\_SOURCE ||--o{ FACT\_PRICE : "provides"

&#x20;   DIM\_PRODUCT ||--o{ FACT\_PRICE : "priced\_as"



&#x20;   DIM\_DATE ||--o{ FACT\_GOLD\_FX : "has"

&#x20;   DIM\_SOURCE ||--o{ FACT\_GOLD\_FX : "provides"

&#x20;   DIM\_CURRENCY ||--o{ FACT\_GOLD\_FX : "priced\_as"



&#x20;   DIM\_SOURCE ||--o{ FACT\_INDICATOR : "provides"

&#x20;   DIM\_INDICATOR ||--o{ FACT\_INDICATOR : "describes"



&#x20;   DIM\_DATE {

&#x20;       int date\_key PK

&#x20;       date full\_date

&#x20;       smallint day\_of\_month

&#x20;       smallint day\_of\_week

&#x20;       smallint week\_of\_year

&#x20;       smallint month

&#x20;       string month\_name

&#x20;       smallint quarter

&#x20;       smallint year

&#x20;   }



&#x20;   DIM\_SOURCE {

&#x20;       int source\_key PK

&#x20;       string source\_name UK

&#x20;       string source\_type

&#x20;   }



&#x20;   DIM\_PRODUCT {

&#x20;       int product\_key PK

&#x20;       string product\_id

&#x20;       string name

&#x20;       string category

&#x20;       string unit

&#x20;       date valid\_from

&#x20;       date valid\_to

&#x20;       boolean is\_current

&#x20;   }



&#x20;   DIM\_CURRENCY {

&#x20;       int currency\_key PK

&#x20;       string code

&#x20;       string kind

&#x20;       smallint karat

&#x20;   }



&#x20;   DIM\_INDICATOR {

&#x20;       int indicator\_key PK

&#x20;       string indicator\_code UK

&#x20;       string indicator\_name

&#x20;       string unit

&#x20;       string frequency

&#x20;   }



&#x20;   FACT\_PRICE {

&#x20;       int product\_key PK, FK

&#x20;       int source\_key PK, FK

&#x20;       int date\_key PK, FK

&#x20;       decimal price

&#x20;       decimal unit\_price

&#x20;       timestamp loaded\_at

&#x20;   }



&#x20;   FACT\_GOLD\_FX {

&#x20;       int currency\_key PK, FK

&#x20;       int source\_key PK, FK

&#x20;       int date\_key PK, FK

&#x20;       decimal rate

&#x20;       timestamp loaded\_at

&#x20;   }



&#x20;   FACT\_INDICATOR {

&#x20;       int indicator\_key PK, FK

&#x20;       int source\_key PK, FK

&#x20;       string country PK

&#x20;       smallint period\_year PK

&#x20;       smallint period\_month PK

&#x20;       decimal value

&#x20;       timestamp loaded\_at

&#x20;   }

