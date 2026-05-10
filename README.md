# 🥗 Hướng Dẫn Xây Dựng Hệ Thống BI Dinh Dưỡng Thông Minh — CẬP NHẬT THEO FOOD.COM DATASET
### Dataset thực tế: Food.com Recipes & Interactions (Kaggle – shuyangli94)
### Tech Stack: SQL Server · SSIS · SSAS · ASP.NET Core

---

> **📂 Dataset nguồn:**
> - `RAW_recipes.csv` — 231.638 công thức, 12 cột
> - `RAW_interactions.csv` — 1.132.367 đánh giá, 5 cột
> - **Link:** https://www.kaggle.com/datasets/shuyangli94/food-com-recipes-and-user-interactions

---

## 🗂 CẤU TRÚC DỮ LIỆU THỰC TẾ (PHẢI NẮM RÕ TRƯỚC KHI LÀM)

### RAW_recipes.csv — 12 cột

| Cột | Kiểu | Mô tả | Ví dụ |
|-----|------|--------|-------|
| `name` | string | Tên công thức | "arriba baked winter squash mexican style" |
| `id` | int | Recipe ID (khóa chính) | 137739 |
| `minutes` | int | Tổng thời gian chuẩn bị (phút) | 55 |
| `contributor_id` | int | ID người đăng | 47892 |
| `submitted` | date | Ngày đăng | 2005-09-16 |
| `tags` | string (list) | Danh sách tag dạng chuỗi | "['60-minutes-or-less','vegetables',...]" |
| `nutrition` | string (list) | **[calories, total_fat%DV, sugar%DV, sodium%DV, protein%DV, saturated_fat%DV, carbs%DV]** | "[51.5, 0.0, 13.0, 0.0, 2.0, 0.0, 4.0]" |
| `n_steps` | int | Số bước thực hiện | 11 |
| `steps` | string (list) | Các bước nấu | "['make a choice and proceed...']" |
| `description` | string | Mô tả công thức | "autumn is a wonderful season..." |
| `ingredients` | string (list) | Nguyên liệu | "['winter squash','butter',...]" |
| `n_ingredients` | int | Số lượng nguyên liệu | 7 |

> ⚠️ **Lưu ý quan trọng:** Cột `nutrition` lưu dạng `"[calories, fat%DV, sugar%DV, sodium%DV, protein%DV, saturated_fat%DV, carbs%DV]"`.  
> **PDV = Percentage of Daily Value** — không phải gram tuyệt đối. Cần quy đổi trong SSIS.

### RAW_interactions.csv — 5 cột

| Cột | Kiểu | Mô tả | Ví dụ |
|-----|------|--------|-------|
| `user_id` | int | ID người dùng | 38094 |
| `recipe_id` | int | ID công thức (FK → recipes.id) | 40893 |
| `date` | date | Ngày tương tác | 2003-04-24 |
| `rating` | int | Điểm đánh giá (1–5) | 4 |
| `review` | string | Nội dung đánh giá | "Good but needed extra..." |

---

## BƯỚC 1 — THIẾT KẾ DATABASE (STAR SCHEMA THEO FOODCOM)

### 1.1 Sơ đồ Star Schema

```
                        ┌──────────────────────┐
                        │      Dim_Time         │
                        │──────────────────────│
                        │ TimeKey (PK)          │  ← Generate từ cột
                        │ FullDate              │    'submitted' (recipes)
                        │ Day                   │    và 'date' (interactions)
                        │ Month / MonthName     │
                        │ Quarter / Year        │
                        │ WeekDayName           │
                        │ IsWeekend             │
                        └──────────┬───────────┘
                                   │
┌─────────────────────┐   ┌────────▼──────────────────────────────────────┐
│    Dim_Recipes       │   │               Fact_RecipeInteraction           │
│─────────────────────│   │───────────────────────────────────────────────│
│ RecipeKey (PK)  ────┼──►│ InteractionID   (PK – IDENTITY)               │
│ RecipeID (NK)        │   │ RecipeKey       (FK → Dim_Recipes)            │
│ RecipeName           │   │ UserKey         (FK → Dim_Users)              │
│ Minutes              │   │ TimeKey         (FK → Dim_Time)               │
│ ContributorID        │   │ Rating          (1–5)                         │
│ SubmittedDate        │   │ HasReview       (BIT)                         │
│ Tags_Raw             │   │ ReviewLength    (INT, số ký tự)               │
│ NSteps               │   │ ── NUTRITION (tách từ cột nutrition) ──       │
│ NIngredients         │   │ Calories        (DECIMAL – kcal tuyệt đối)   │
│ Description          │   │ TotalFat_PDV    (DECIMAL – %DV)               │
│ Ingredients_Raw      │   │ TotalFat_g      (DECIMAL – quy đổi gram)      │
│ ClusterID            │   │ Sugar_PDV       (DECIMAL – %DV)               │
│ AvgRating            │   │ Sugar_g         (DECIMAL)                     │
│ RatingCount          │   │ Sodium_PDV      (DECIMAL – %DV)               │
│ IsHighProtein (BIT)  │   │ Sodium_mg       (DECIMAL)                     │
│ IsLowCalorie  (BIT)  │   │ Protein_PDV     (DECIMAL – %DV)               │
│ IsQuick       (BIT)  │   │ Protein_g       (DECIMAL – quy đổi gram)      │
└─────────────────────┘   │ SatFat_PDV      (DECIMAL – %DV)               │
                           │ SatFat_g        (DECIMAL)                     │
┌─────────────────────┐   │ Carbs_PDV       (DECIMAL – %DV)               │
│    Dim_Users         │   │ Carbs_g         (DECIMAL – quy đổi gram)      │
│─────────────────────│   │ ── COMPUTED COLUMNS ──                        │
│ UserKey (PK)    ────┼──►│ ProteinRatio_Pct  AS (Protein_g*4/Calories)  │
│ UserID (NK)          │   │ CarbRatio_Pct     AS (Carbs_g*4/Calories)    │
│ FirstInteractDate    │   │ FatRatio_Pct      AS (TotalFat_g*9/Calories) │
│ LastInteractDate     │   │ LoadedDate                                    │
│ TotalReviews         │   └───────────────────────────────────────────────┘
│ AvgRatingGiven       │
│ ActiveYears          │
└─────────────────────┘
```

### 1.2 Quy đổi PDV → Gram (Daily Reference Values của FDA)

```
Total Fat:      %DV × 78g  / 100  → gram
Saturated Fat:  %DV × 20g  / 100  → gram
Sugar:          %DV × 50g  / 100  → gram
Sodium:         %DV × 2300mg/100  → mg
Protein:        %DV × 50g  / 100  → gram
Carbohydrates:  %DV × 275g / 100  → gram
```

### 1.3 DDL — Tạo toàn bộ Database

```sql
-- ================================================================
-- TẠO DATABASE
-- ================================================================
CREATE DATABASE NutritionDW_FoodCom;
GO
USE NutritionDW_FoodCom;
GO

-- ================================================================
-- STAGING TABLES (nhận dữ liệu thô từ SSIS)
-- ================================================================
CREATE TABLE STG_Recipes (
    id              INT            NULL,
    name            NVARCHAR(500)  NULL,
    minutes         INT            NULL,
    contributor_id  INT            NULL,
    submitted       VARCHAR(20)    NULL,
    tags            NVARCHAR(MAX)  NULL,
    nutrition       NVARCHAR(500)  NULL,   -- Raw: "[51.5, 0.0, 13.0, ...]"
    n_steps         INT            NULL,
    steps           NVARCHAR(MAX)  NULL,
    description     NVARCHAR(MAX)  NULL,
    ingredients     NVARCHAR(MAX)  NULL,
    n_ingredients   INT            NULL,
    LoadedDate      DATETIME       DEFAULT GETDATE()
);

CREATE TABLE STG_Interactions (
    user_id    INT            NULL,
    recipe_id  INT            NULL,
    date       VARCHAR(20)    NULL,
    rating     INT            NULL,
    review     NVARCHAR(MAX)  NULL,
    LoadedDate DATETIME       DEFAULT GETDATE()
);
GO

-- ================================================================
-- DIM_TIME — Tự generate cho toàn bộ range 2000–2025
-- ================================================================
CREATE TABLE Dim_Time (
    TimeKey      INT         NOT NULL PRIMARY KEY,  -- YYYYMMDD
    FullDate     DATE        NOT NULL,
    [Day]        TINYINT     NOT NULL,
    [Month]      TINYINT     NOT NULL,
    MonthName    VARCHAR(20) NOT NULL,
    [Quarter]    TINYINT     NOT NULL,
    [Year]       SMALLINT    NOT NULL,
    WeekDay      TINYINT     NOT NULL,
    WeekDayName  VARCHAR(20) NOT NULL,
    IsWeekend    BIT         NOT NULL DEFAULT 0
);

-- Populate Dim_Time 2000–2025
DECLARE @d DATE = '2000-01-01';
WHILE @d <= '2025-12-31'
BEGIN
    INSERT INTO Dim_Time VALUES (
        CONVERT(INT,FORMAT(@d,'yyyyMMdd')),
        @d,
        DAY(@d), MONTH(@d),
        DATENAME(MONTH,@d),
        DATEPART(QUARTER,@d),
        YEAR(@d),
        DATEPART(WEEKDAY,@d),
        DATENAME(WEEKDAY,@d),
        CASE WHEN DATEPART(WEEKDAY,@d) IN (1,7) THEN 1 ELSE 0 END
    );
    SET @d = DATEADD(DAY,1,@d);
END;
GO

-- ================================================================
-- DIM_RECIPES — Từ RAW_recipes.csv (sau khi parse nutrition)
-- ================================================================
CREATE TABLE Dim_Recipes (
    RecipeKey       INT            NOT NULL IDENTITY(1,1) PRIMARY KEY,
    RecipeID        INT            NOT NULL UNIQUE,        -- = id trong CSV
    RecipeName      NVARCHAR(500)  NOT NULL,
    Minutes         INT            NULL,                   -- = minutes
    ContributorID   INT            NULL,                   -- = contributor_id
    SubmittedDate   DATE           NULL,                   -- = submitted (parsed)
    Tags_Raw        NVARCHAR(MAX)  NULL,                   -- = tags (chuỗi gốc)
    NSteps          INT            NULL,                   -- = n_steps
    NIngredients    INT            NULL,                   -- = n_ingredients
    Description     NVARCHAR(MAX)  NULL,
    Ingredients_Raw NVARCHAR(MAX)  NULL,
    -- Nutrition (tách từ cột nutrition)
    Calories        DECIMAL(10,2)  NULL,
    TotalFat_PDV    DECIMAL(8,2)   NULL,
    Sugar_PDV       DECIMAL(8,2)   NULL,
    Sodium_PDV      DECIMAL(8,2)   NULL,
    Protein_PDV     DECIMAL(8,2)   NULL,
    SatFat_PDV      DECIMAL(8,2)   NULL,
    Carbs_PDV       DECIMAL(8,2)   NULL,
    -- Quy đổi sang gram/mg
    TotalFat_g      AS (TotalFat_PDV * 78.0  / 100) PERSISTED,
    Sugar_g         AS (Sugar_PDV   * 50.0  / 100) PERSISTED,
    Sodium_mg       AS (Sodium_PDV  * 2300.0/ 100) PERSISTED,
    Protein_g       AS (Protein_PDV * 50.0  / 100) PERSISTED,
    SatFat_g        AS (SatFat_PDV  * 20.0  / 100) PERSISTED,
    Carbs_g         AS (Carbs_PDV   * 275.0 / 100) PERSISTED,
    -- Flags phân loại nhanh
    IsHighProtein   AS (CASE WHEN Protein_PDV > 20 THEN 1 ELSE 0 END) PERSISTED,
    IsLowCalorie    AS (CASE WHEN Calories < 300    THEN 1 ELSE 0 END) PERSISTED,
    IsQuick         AS (CASE WHEN Minutes   <= 30   THEN 1 ELSE 0 END) PERSISTED,
    IsVegetarian    AS (CASE WHEN Tags_Raw LIKE '%vegetarian%' THEN 1 ELSE 0 END) PERSISTED,
    -- Aggregates (cập nhật sau khi load Interactions)
    AvgRating       DECIMAL(4,2)   NULL,
    RatingCount     INT            NULL DEFAULT 0,
    -- Data Mining result
    ClusterID       TINYINT        NULL,
    ClusterLabel    NVARCHAR(50)   NULL,
    -- Metadata
    IsActive        BIT            NOT NULL DEFAULT 1,
    LoadedDate      DATETIME       NOT NULL DEFAULT GETDATE()
);

-- ================================================================
-- DIM_USERS — Từ RAW_interactions.csv (aggregate per user_id)
-- ================================================================
CREATE TABLE Dim_Users (
    UserKey             INT         NOT NULL IDENTITY(1,1) PRIMARY KEY,
    UserID              INT         NOT NULL UNIQUE,          -- = user_id
    FirstInteractDate   DATE        NULL,
    LastInteractDate    DATE        NULL,
    TotalReviews        INT         NULL DEFAULT 0,
    AvgRatingGiven      DECIMAL(4,2)NULL,
    ActiveYears         AS (DATEDIFF(YEAR, FirstInteractDate, LastInteractDate)) PERSISTED,
    -- Phân loại hành vi người dùng (tính sau Data Mining)
    UserSegment         NVARCHAR(50) NULL,  -- e.g., Power User / Casual / Critic
    LoadedDate          DATETIME    NOT NULL DEFAULT GETDATE()
);

-- ================================================================
-- FACT_RECIPEINTERACTION — Bảng Fact chính
-- ================================================================
CREATE TABLE Fact_RecipeInteraction (
    InteractionID    BIGINT         NOT NULL IDENTITY(1,1) PRIMARY KEY,
    RecipeKey        INT            NOT NULL,
    UserKey          INT            NOT NULL,
    TimeKey          INT            NOT NULL,
    -- Từ RAW_interactions
    Rating           TINYINT        NULL,        -- 1–5
    HasReview        BIT            NOT NULL DEFAULT 0,
    ReviewLength     INT            NULL,        -- số ký tự review
    -- Nutrition snapshot (denormalized từ Dim_Recipes tại thời điểm load)
    Calories         DECIMAL(10,2)  NULL,
    TotalFat_PDV     DECIMAL(8,2)   NULL,
    Sugar_PDV        DECIMAL(8,2)   NULL,
    Sodium_PDV       DECIMAL(8,2)   NULL,
    Protein_PDV      DECIMAL(8,2)   NULL,
    SatFat_PDV       DECIMAL(8,2)   NULL,
    Carbs_PDV        DECIMAL(8,2)   NULL,
    -- Gram equivalents (computed)
    Protein_g        AS (Protein_PDV * 50.0  / 100) PERSISTED,
    Carbs_g          AS (Carbs_PDV   * 275.0 / 100) PERSISTED,
    TotalFat_g       AS (TotalFat_PDV* 78.0  / 100) PERSISTED,
    -- Macro ratios (computed)
    ProteinRatio_Pct AS (
        CASE WHEN Calories > 0
             THEN (Protein_PDV * 50.0 / 100) * 4.0 / Calories * 100
             ELSE NULL END
    ) PERSISTED,
    CarbRatio_Pct    AS (
        CASE WHEN Calories > 0
             THEN (Carbs_PDV * 275.0 / 100) * 4.0 / Calories * 100
             ELSE NULL END
    ) PERSISTED,
    FatRatio_Pct     AS (
        CASE WHEN Calories > 0
             THEN (TotalFat_PDV * 78.0 / 100) * 9.0 / Calories * 100
             ELSE NULL END
    ) PERSISTED,
    -- Metadata
    LoadedDate       DATETIME       NOT NULL DEFAULT GETDATE(),
    -- FK
    CONSTRAINT FK_Fact_Recipe FOREIGN KEY (RecipeKey) REFERENCES Dim_Recipes(RecipeKey),
    CONSTRAINT FK_Fact_User   FOREIGN KEY (UserKey)   REFERENCES Dim_Users(UserKey),
    CONSTRAINT FK_Fact_Time   FOREIGN KEY (TimeKey)   REFERENCES Dim_Time(TimeKey)
);

-- INDEXES
CREATE INDEX IX_Fact_RecipeKey ON Fact_RecipeInteraction(RecipeKey);
CREATE INDEX IX_Fact_UserKey   ON Fact_RecipeInteraction(UserKey);
CREATE INDEX IX_Fact_TimeKey   ON Fact_RecipeInteraction(TimeKey);
CREATE INDEX IX_Fact_Rating    ON Fact_RecipeInteraction(Rating);
GO

-- ================================================================
-- STORED PROCEDURE: Parse cột nutrition (gọi từ SSIS SQL Task)
-- ================================================================
CREATE PROCEDURE sp_ParseNutrition
AS
BEGIN
    SET NOCOUNT ON;

    -- Cột nutrition trong STG có dạng: "[51.5, 0.0, 13.0, 0.0, 2.0, 0.0, 4.0]"
    -- Thứ tự: calories, total_fat%DV, sugar%DV, sodium%DV, protein%DV, satfat%DV, carbs%DV

    UPDATE s
    SET
        Calories     = TRY_CAST(TRIM(PARSENAME(REPLACE(clean,',','.'), 7)) AS DECIMAL(10,2)),
        TotalFat_PDV = TRY_CAST(TRIM(PARSENAME(REPLACE(clean,',','.'), 6)) AS DECIMAL(8,2)),
        Sugar_PDV    = TRY_CAST(TRIM(PARSENAME(REPLACE(clean,',','.'), 5)) AS DECIMAL(8,2)),
        Sodium_PDV   = TRY_CAST(TRIM(PARSENAME(REPLACE(clean,',','.'), 4)) AS DECIMAL(8,2)),
        Protein_PDV  = TRY_CAST(TRIM(PARSENAME(REPLACE(clean,',','.'), 3)) AS DECIMAL(8,2)),
        SatFat_PDV   = TRY_CAST(TRIM(PARSENAME(REPLACE(clean,',','.'), 2)) AS DECIMAL(8,2)),
        Carbs_PDV    = TRY_CAST(TRIM(PARSENAME(REPLACE(clean,',','.'), 1)) AS DECIMAL(8,2))
    FROM (
        SELECT
            RecipeID,
            -- Bỏ dấu ngoặc vuông, giữ 7 số cách nhau bằng dấu phẩy
            REPLACE(REPLACE(nutrition,'[',''),']','') AS clean
        FROM STG_Recipes
        WHERE nutrition IS NOT NULL
    ) s
    JOIN Dim_Recipes dr ON s.RecipeID = dr.RecipeID;

    PRINT 'Nutrition parsed successfully';
END;
GO
```

---

## BƯỚC 2 — QUY TRÌNH SSIS (ETL PIPELINE THEO FOODCOM)

### 2.1 Tổng quan luồng ETL

```
RAW_recipes.csv ──────────────────────────────────────────────┐
                                                               ▼
                  [SSIS Package: NutritionBI_FoodCom.dtsx]
                  ┌────────────────────────────────────────────┐
                  │  Control Flow                               │
                  │  ① Truncate All Staging Tables             │
                  │      ↓                                      │
                  │  ② DFT: Load RAW_recipes → STG_Recipes     │
                  │      ↓                                      │
                  │  ③ DFT: Load RAW_interactions → STG_Inter  │
                  │      ↓                                      │
                  │  ④ SQL Task: Parse nutrition column         │
                  │      ↓                                      │
                  │  ⑤ DFT: STG_Recipes → Dim_Recipes          │
                  │      ↓                                      │
                  │  ⑥ DFT: STG_Interactions → Dim_Users       │
                  │      ↓                                      │
                  │  ⑦ DFT: JOIN STG → Fact_RecipeInteraction  │
                  │      ↓                                      │
                  │  ⑧ SQL Task: Update AvgRating in Dim_Recipes│
                  │      ↓                                      │
                  │  ⑨ Script Task: Log & Notify               │
                  └────────────────────────────────────────────┘
RAW_interactions.csv ─────────────────────────────────────────┘
```

### 2.2 Cấu hình Connection Managers

**Flat File Connection – RAW_recipes.csv:**
```
Name:           FF_RAW_Recipes
File name:      C:\ETL_Input\RAW_recipes.csv
Format:         Delimited
Header row del: {CR}{LF}
Text qualifier: " (nháy kép – BẮT BUỘC vì tags/steps có dấu phẩy bên trong)
Code page:      65001 (UTF-8)
Columns tab:    Delimiter = Comma (,)
Columns:        name | id | minutes | contributor_id | submitted |
                tags | nutrition | n_steps | steps |
                description | ingredients | n_ingredients
```

**Flat File Connection – RAW_interactions.csv:**
```
Name:           FF_RAW_Interactions
File name:      C:\ETL_Input\RAW_interactions.csv
Format:         Delimited
Text qualifier: " (nháy kép)
Code page:      65001 (UTF-8)
Columns:        user_id | recipe_id | date | rating | review
```

**OLE DB Connection – SQL Server:**
```
Name:     OLEDB_NutritionDW
Provider: Microsoft OLE DB Driver for SQL Server
Server:   .\SQLEXPRESS
Database: NutritionDW_FoodCom
Auth:     Windows Authentication
```

### 2.3 Task ① — Execute SQL Task: Truncate Staging

```sql
TRUNCATE TABLE STG_Recipes;
TRUNCATE TABLE STG_Interactions;
PRINT 'Staging tables cleared at: ' + CONVERT(VARCHAR, GETDATE());
```

### 2.4 Task ② — Data Flow: RAW_recipes → STG_Recipes

```
[Flat File Source: FF_RAW_Recipes]
        │  Output columns: name, id, minutes, contributor_id,
        │                   submitted, tags, nutrition, n_steps,
        │                   steps, description, ingredients, n_ingredients
        ↓
[Data Conversion Transform]
  Chuyển đổi kiểu dữ liệu:
  • id             : string → DT_I4    (integer)
  • minutes        : string → DT_I4
  • contributor_id : string → DT_I4
  • n_steps        : string → DT_I4
  • n_ingredients  : string → DT_I4
  • name           : string → DT_WSTR(500)  (Unicode)
  • description    : string → DT_NTEXT
  • tags           : string → DT_NTEXT
  • nutrition      : string → DT_WSTR(500)
  • submitted      : string → DT_WSTR(20)   (parse thủ công sau)
  • steps          : string → DT_NTEXT
  • ingredients    : string → DT_NTEXT
        ↓
[Conditional Split Transform]
  Condition VALID:
    !ISNULL([Copy of id])
    && [Copy of id] > 0
    && !ISNULL([Copy of name])
    && LEN(TRIM([Copy of name])) > 0
    && [Copy of minutes] < 259200  (loại bỏ > 6 tháng – outlier)
    && [Copy of minutes] > 0
  Condition INVALID: default → Flat File Destination (ErrorLog_Recipes.txt)
        ↓ (VALID)
[Derived Column Transform]
  • LoadedDate = (DT_DBDATE)GETDATE()
        ↓
[OLE DB Destination: STG_Recipes]
  Access mode: Table or view – fast load
  Table: STG_Recipes
  Batch size: 10000
  Mapping: tất cả các cột tương ứng
```

### 2.5 Task ③ — Data Flow: RAW_interactions → STG_Interactions

```
[Flat File Source: FF_RAW_Interactions]
        ↓
[Data Conversion Transform]
  • user_id   : string → DT_I4
  • recipe_id : string → DT_I4
  • rating    : string → DT_I1   (tiny int, 1–5)
  • date      : string → DT_WSTR(20)
  • review    : string → DT_NTEXT
        ↓
[Conditional Split]
  VALID: [Copy of rating] >= 1 && [Copy of rating] <= 5
         && [Copy of user_id] > 0
         && [Copy of recipe_id] > 0
  INVALID: → ErrorLog_Interactions.txt
        ↓ (VALID)
[OLE DB Destination: STG_Interactions]
  Batch size: 50000  (file lớn hơn – 1M+ rows)
```

### 2.6 Task ④ — Execute SQL Task: Parse Nutrition Column

```sql
-- Bước 4a: Thêm các cột nutrition vào STG_Recipes nếu chưa có
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'STG_Recipes' AND COLUMN_NAME = 'Calories'
)
BEGIN
    ALTER TABLE STG_Recipes
        ADD Calories     DECIMAL(10,2) NULL,
            TotalFat_PDV DECIMAL(8,2)  NULL,
            Sugar_PDV    DECIMAL(8,2)  NULL,
            Sodium_PDV   DECIMAL(8,2)  NULL,
            Protein_PDV  DECIMAL(8,2)  NULL,
            SatFat_PDV   DECIMAL(8,2)  NULL,
            Carbs_PDV    DECIMAL(8,2)  NULL;
END;

-- Bước 4b: Parse cột nutrition dạng "[v1, v2, v3, v4, v5, v6, v7]"
-- Dùng STRING_SPLIT (SQL Server 2016+) với row_number trick
WITH Parsed AS (
    SELECT
        id,
        nutrition,
        -- Bỏ ngoặc vuông
        REPLACE(REPLACE(nutrition,'[',''),']','') AS clean_nutrition
    FROM STG_Recipes
    WHERE nutrition IS NOT NULL AND nutrition <> ''
),
Split AS (
    SELECT
        p.id,
        TRIM(value) AS val,
        ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY (SELECT NULL)) AS pos
    FROM Parsed p
    CROSS APPLY STRING_SPLIT(p.clean_nutrition, ',')
)
UPDATE STG_Recipes
SET
    Calories     = (SELECT TRY_CAST(val AS DECIMAL(10,2)) FROM Split WHERE id=s.id AND pos=1),
    TotalFat_PDV = (SELECT TRY_CAST(val AS DECIMAL(8,2))  FROM Split WHERE id=s.id AND pos=2),
    Sugar_PDV    = (SELECT TRY_CAST(val AS DECIMAL(8,2))  FROM Split WHERE id=s.id AND pos=3),
    Sodium_PDV   = (SELECT TRY_CAST(val AS DECIMAL(8,2))  FROM Split WHERE id=s.id AND pos=4),
    Protein_PDV  = (SELECT TRY_CAST(val AS DECIMAL(8,2))  FROM Split WHERE id=s.id AND pos=5),
    SatFat_PDV   = (SELECT TRY_CAST(val AS DECIMAL(8,2))  FROM Split WHERE id=s.id AND pos=6),
    Carbs_PDV    = (SELECT TRY_CAST(val AS DECIMAL(8,2))  FROM Split WHERE id=s.id AND pos=7)
FROM STG_Recipes s
WHERE s.nutrition IS NOT NULL;

PRINT 'Nutrition column parsed: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows';
```

### 2.7 Task ⑤ — Data Flow: STG_Recipes → Dim_Recipes (SCD Type 1)

```
[OLE DB Source]
  SQL Command:
    SELECT
        id              AS RecipeID,
        name            AS RecipeName,
        minutes         AS Minutes,
        contributor_id  AS ContributorID,
        TRY_CAST(submitted AS DATE) AS SubmittedDate,
        tags            AS Tags_Raw,
        n_steps         AS NSteps,
        n_ingredients   AS NIngredients,
        description,
        ingredients     AS Ingredients_Raw,
        -- Nutrition (đã parse)
        Calories, TotalFat_PDV, Sugar_PDV, Sodium_PDV,
        Protein_PDV, SatFat_PDV, Carbs_PDV
    FROM STG_Recipes
    WHERE id IS NOT NULL AND Calories IS NOT NULL
        ↓
[Lookup Transform]
  Connection: OLEDB_NutritionDW
  Query: SELECT RecipeID, RecipeKey FROM Dim_Recipes
  Join: [RecipeID] = [RecipeID]
  Match Output:    → UPDATE path (recipe đã tồn tại)
  No Match Output: → INSERT path (recipe mới)
        ↓ (No Match – INSERT)
[OLE DB Destination: Dim_Recipes]
  Mode: Fast Load, Batch 5000
  Mapping: RecipeID, RecipeName, Minutes, ContributorID,
            SubmittedDate, Tags_Raw, NSteps, NIngredients,
            Description, Ingredients_Raw,
            Calories, TotalFat_PDV, Sugar_PDV, Sodium_PDV,
            Protein_PDV, SatFat_PDV, Carbs_PDV

        ↓ (Match – UPDATE với OLE DB Command)
[OLE DB Command Transform]
  SQL: UPDATE Dim_Recipes SET
            RecipeName=?, Minutes=?, NSteps=?,
            NIngredients=?, Calories=?, Protein_PDV=?,
            Carbs_PDV=?, TotalFat_PDV=?, Sugar_PDV=?,
            Sodium_PDV=?, SatFat_PDV=?
       WHERE RecipeID=?
```

### 2.8 Task ⑥ — Data Flow: STG_Interactions → Dim_Users

```
[OLE DB Source]
  SQL Command:
    SELECT
        user_id,
        MIN(TRY_CAST(date AS DATE)) AS FirstInteractDate,
        MAX(TRY_CAST(date AS DATE)) AS LastInteractDate,
        COUNT(*)                    AS TotalReviews,
        AVG(CAST(rating AS FLOAT))  AS AvgRatingGiven
    FROM STG_Interactions
    WHERE user_id IS NOT NULL AND rating BETWEEN 1 AND 5
    GROUP BY user_id
        ↓
[Lookup Transform]
  Query: SELECT UserID, UserKey FROM Dim_Users
  No Match → INSERT Dim_Users
  Match    → UPDATE (upsert TotalReviews, AvgRatingGiven, LastInteractDate)
```

### 2.9 Task ⑦ — Data Flow: Fact_RecipeInteraction (Bảng chính)

```
[OLE DB Source]
  SQL Command:
    SELECT
        si.user_id,
        si.recipe_id,
        TRY_CAST(si.date AS DATE)  AS InteractDate,
        si.rating,
        CASE WHEN LEN(TRIM(si.review)) > 0 THEN 1 ELSE 0 END AS HasReview,
        LEN(si.review)             AS ReviewLength,
        -- Nutrition snapshot từ Dim_Recipes tại thời điểm load
        dr.Calories,
        dr.TotalFat_PDV,
        dr.Sugar_PDV,
        dr.Sodium_PDV,
        dr.Protein_PDV,
        dr.SatFat_PDV,
        dr.Carbs_PDV,
        -- Keys từ Dimension tables
        dr.RecipeKey,
        du.UserKey,
        dt.TimeKey
    FROM STG_Interactions si
    JOIN Dim_Recipes dr ON si.recipe_id = dr.RecipeID
    JOIN Dim_Users   du ON si.user_id   = du.UserID
    JOIN Dim_Time    dt ON dt.FullDate  = TRY_CAST(si.date AS DATE)
    WHERE si.rating BETWEEN 1 AND 5
        ↓
[OLE DB Destination: Fact_RecipeInteraction]
  Mode: Fast Load
  Batch size: 50000
  Table lock: ON
  Keep identity: OFF
```

### 2.10 Task ⑧ — Execute SQL Task: Cập nhật AvgRating vào Dim_Recipes

```sql
-- Sau khi Fact đã load xong, update aggregate vào Dim
UPDATE dr
SET
    AvgRating   = agg.AvgRating,
    RatingCount = agg.RatingCount
FROM Dim_Recipes dr
JOIN (
    SELECT
        RecipeKey,
        AVG(CAST(Rating AS FLOAT)) AS AvgRating,
        COUNT(*)                   AS RatingCount
    FROM Fact_RecipeInteraction
    WHERE Rating IS NOT NULL
    GROUP BY RecipeKey
) agg ON dr.RecipeKey = agg.RecipeKey;

PRINT 'Updated AvgRating for ' + CAST(@@ROWCOUNT AS VARCHAR) + ' recipes';
```

### 2.11 Task ⑨ — Script Task: Log kết quả

```csharp
// C# Script Task – ghi log ETL summary
using System;
using System.IO;
using Microsoft.SqlServer.Dts.Runtime;

public void Main()
{
    string logPath = @"C:\ETL_Logs\NutritionBI_" +
                     DateTime.Now.ToString("yyyyMMdd") + ".log";

    string msg = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] ETL COMPLETED\n" +
                 $"  Recipes loaded:      {Dts.Variables["User::RecipeCount"].Value}\n" +
                 $"  Interactions loaded: {Dts.Variables["User::InteractionCount"].Value}\n" +
                 $"  Errors:              {Dts.Variables["User::ErrorCount"].Value}\n" +
                 $"  Duration:            {Dts.Variables["User::DurationSec"].Value}s\n";

    File.AppendAllText(logPath, msg + "\n");
    Dts.TaskResult = (int)ScriptResults.Success;
}
```

---

## BƯỚC 3 — XÂY DỰNG OLAP CUBE & DATA MINING (SSAS THEO FOODCOM)

### 3.1 Tạo SSAS Project

```
Visual Studio → New Project
→ "Analysis Services Multidimensional and Data Mining Project"
→ Name: NutritionBI_SSAS_FoodCom
```

### 3.2 Data Source & Data Source View

**Data Source:**
```
→ Data Sources → New Data Source
→ Connection: NutritionDW_FoodCom (SQL Server)
→ Name: DS_FoodCom
```

**Data Source View (DSV) — Chọn các bảng:**
```
Tables cần add:
✅ Fact_RecipeInteraction  (Fact table – trung tâm)
✅ Dim_Recipes             (Recipe dimension)
✅ Dim_Users               (User dimension)
✅ Dim_Time                (Time dimension)

Verify joins:
  Fact.RecipeKey → Dim_Recipes.RecipeKey ✅
  Fact.UserKey   → Dim_Users.UserKey     ✅
  Fact.TimeKey   → Dim_Time.TimeKey      ✅
```

**Named Calculations bổ sung trong DSV:**
```sql
-- Trong Fact_RecipeInteraction:

-- 1. RatingCategory
CASE
    WHEN Rating = 5 THEN 'Excellent (5★)'
    WHEN Rating = 4 THEN 'Good (4★)'
    WHEN Rating = 3 THEN 'Average (3★)'
    WHEN Rating IN (1,2) THEN 'Poor (1-2★)'
    ELSE 'Unrated'
END

-- 2. CalorieCategory (dựa trên Calories)
CASE
    WHEN Calories < 200  THEN 'Very Low (<200)'
    WHEN Calories < 400  THEN 'Low (200-400)'
    WHEN Calories < 600  THEN 'Medium (400-600)'
    WHEN Calories < 800  THEN 'High (600-800)'
    ELSE 'Very High (800+)'
END

-- Trong Dim_Recipes:
-- 3. TimeCategory
CASE
    WHEN Minutes <= 15  THEN 'Ultra Quick (≤15m)'
    WHEN Minutes <= 30  THEN 'Quick (16-30m)'
    WHEN Minutes <= 60  THEN 'Moderate (31-60m)'
    WHEN Minutes <= 120 THEN 'Long (1-2h)'
    ELSE 'Very Long (2h+)'
END

-- 4. NutritionScore (điểm tổng hợp 0-100)
CASE
    WHEN Calories IS NULL THEN 0
    ELSE
        (CASE WHEN Protein_PDV BETWEEN 10 AND 40 THEN 30 ELSE 0 END) +
        (CASE WHEN Carbs_PDV   BETWEEN 20 AND 60 THEN 30 ELSE 0 END) +
        (CASE WHEN TotalFat_PDV < 30              THEN 25 ELSE 0 END) +
        (CASE WHEN Calories < 600                 THEN 15 ELSE 0 END)
END
```

### 3.3 Tạo OLAP Cube

**Cube Wizard:**
```
Step 1: Use existing tables
Step 2: Measure Group: Fact_RecipeInteraction
Step 3: Measures chọn:
  ✅ Rating (Sum)                   → đổi tên: Sum of Ratings
  ✅ Has Review (Sum)               → đổi tên: Total Reviews
  ✅ Review Length (Sum)
  ✅ Calories (Sum + Avg)
  ✅ Protein_PDV (Sum + Avg)
  ✅ Carbs_PDV (Sum + Avg)
  ✅ Total Fat_PDV (Sum + Avg)
  ✅ Sugar_PDV (Avg)
  ✅ Sodium_PDV (Avg)
  [Add] Count of Records           → InteractionID Count
Step 4: Dimensions:
  ✅ Dim_Time      (chọn Time dimension type)
  ✅ Dim_Recipes
  ✅ Dim_Users
Name: FoodCom Nutrition Cube
```

**Cấu hình Dim_Time:**
```
Type: Time
Key Column: TimeKey
Attributes:
  - Year       (Type: Years,    KeyColumn: Year)
  - Quarter    (Type: Quarters, KeyColumn: Quarter)
  - Month      (Type: Months,   KeyColumn: Month, NameColumn: MonthName)
  - Day        (Type: Days,     KeyColumn: FullDate)
  - WeekDay    (KeyColumn: WeekDay, NameColumn: WeekDayName)
  - IsWeekend  (KeyColumn: IsWeekend)

Hierarchies:
  → Calendar: Year → Quarter → Month → Day
  → Week: Year → WeekDay
```

**Cấu hình Dim_Recipes:**
```
Key Attribute: RecipeID (Name: RecipeName)

Attributes:
  - RecipeName (key)
  - NSteps         → "Complexity by Steps"
  - NIngredients   → "Complexity by Ingredients"
  - Minutes        (KeyColumn: Minutes, NameColumn: TimeCategory)
  - Calories       (KeyColumn: Calories, NameColumn: CalorieCategory)
  - IsHighProtein
  - IsLowCalorie
  - IsQuick
  - IsVegetarian
  - ClusterID      → "Recipe Cluster"
  - ClusterLabel
  - AvgRating      (KPI dimension)

Hierarchies:
  → Recipe Nutrition: CalorieCategory → RecipeName
  → Recipe Complexity: TimeCategory → RecipeName
  → Recipe Cluster: ClusterLabel → RecipeName
```

**Cấu hình Dim_Users:**
```
Key Attribute: UserID

Attributes:
  - TotalReviews
  - AvgRatingGiven
  - ActiveYears
  - UserSegment

Hierarchy:
  → User Behavior: UserSegment → UserID
```

**Calculated Members trong Cube:**
```mdx
-- Avg Rating (tính đúng từ Sum/Count)
CREATE MEMBER CURRENTCUBE.[Measures].[Avg Rating]
AS
    IIF([Measures].[Interaction Count] = 0, NULL,
        [Measures].[Sum of Ratings] / [Measures].[Interaction Count]
    ), FORMAT_STRING = "#0.00", VISIBLE = 1;

-- Avg Calories per Recipe
CREATE MEMBER CURRENTCUBE.[Measures].[Avg Calories]
AS
    IIF([Measures].[Interaction Count] = 0, NULL,
        [Measures].[Calories] / [Measures].[Interaction Count]
    ), FORMAT_STRING = "#,##0.0", VISIBLE = 1;

-- Protein Ratio %
CREATE MEMBER CURRENTCUBE.[Measures].[Protein Ratio %]
AS
    IIF([Measures].[Calories] = 0, NULL,
        ([Measures].[Protein_PDV] / [Measures].[Interaction Count])
        * 50.0 / 100 * 4.0
        / ([Measures].[Calories] / [Measures].[Interaction Count])
        * 100
    ), FORMAT_STRING = "#0.0", VISIBLE = 1;

-- Carb Ratio %
CREATE MEMBER CURRENTCUBE.[Measures].[Carb Ratio %]
AS
    IIF([Measures].[Calories] = 0, NULL,
        ([Measures].[Carbs_PDV] / [Measures].[Interaction Count])
        * 275.0 / 100 * 4.0
        / ([Measures].[Calories] / [Measures].[Interaction Count])
        * 100
    ), FORMAT_STRING = "#0.0", VISIBLE = 1;

-- Fat Ratio %
CREATE MEMBER CURRENTCUBE.[Measures].[Fat Ratio %]
AS
    IIF([Measures].[Calories] = 0, NULL,
        ([Measures].[Total Fat_PDV] / [Measures].[Interaction Count])
        * 78.0 / 100 * 9.0
        / ([Measures].[Calories] / [Measures].[Interaction Count])
        * 100
    ), FORMAT_STRING = "#0.0", VISIBLE = 1;

-- Review Rate %
CREATE MEMBER CURRENTCUBE.[Measures].[Review Rate %]
AS
    IIF([Measures].[Interaction Count] = 0, NULL,
        [Measures].[Total Reviews] / [Measures].[Interaction Count] * 100
    ), FORMAT_STRING = "#0.0%", VISIBLE = 1;
```

### 3.4 KPI — Key Performance Indicators

```mdx
-- KPI: Recipe Quality Score
CREATE KPI CURRENTCUBE.[Recipe Quality]
AS KpiValue     = [Measures].[Avg Rating],
   KpiGoal      = 4.0,
   KpiStatus    = CASE
                    WHEN KpiValue >= 4.5 THEN 1
                    WHEN KpiValue >= 3.5 THEN 0
                    ELSE -1
                  END,
   KpiTrend     = 0;
```

### 3.5 Data Mining — Clustering Công Thức Ăn

**Mining Input Query (từ NutritionDW):**
```sql
SELECT
    dr.RecipeID,
    dr.RecipeName,
    dr.Minutes,
    dr.NSteps,
    dr.NIngredients,
    dr.Calories,
    dr.TotalFat_PDV,
    dr.Sugar_PDV,
    dr.Sodium_PDV,
    dr.Protein_PDV,
    dr.SatFat_PDV,
    dr.Carbs_PDV,
    -- Derived nutrition gram values
    dr.Protein_g,
    dr.Carbs_g,
    dr.TotalFat_g,
    dr.Sugar_g,
    -- Aggregates từ interactions
    dr.AvgRating,
    dr.RatingCount,
    -- Computed flags
    dr.IsHighProtein,
    dr.IsLowCalorie,
    dr.IsQuick
FROM Dim_Recipes dr
WHERE dr.Calories > 0
  AND dr.Calories < 5000     -- loại outlier cực đoan
  AND dr.Minutes  < 10000    -- loại outlier prep time
  AND dr.RatingCount >= 2    -- chỉ recipe có ít nhất 2 đánh giá
```

**Mining Model Configuration:**
```
Structure: NutritionClustering
Algorithm: Microsoft Clustering

Column Roles:
  RecipeID     → Key
  RecipeName   → Ignore
  Minutes      → Input (continuous)
  NSteps       → Input (continuous)
  NIngredients → Input (continuous)
  Calories     → Input (continuous)  ★ quan trọng nhất
  TotalFat_PDV → Input (continuous)
  Sugar_PDV    → Input (continuous)
  Sodium_PDV   → Input (continuous)
  Protein_PDV  → Input (continuous)  ★ quan trọng
  SatFat_PDV   → Input (continuous)
  Carbs_PDV    → Input (continuous)  ★ quan trọng
  Protein_g    → Input (continuous)
  Carbs_g      → Input (continuous)
  TotalFat_g   → Input (continuous)
  AvgRating    → Input (continuous)
  RatingCount  → Input (continuous)
  IsHighProtein → Input (discrete)
  IsLowCalorie  → Input (discrete)
  IsQuick       → Input (discrete)

Algorithm Parameters:
  CLUSTER_COUNT         = 6
  CLUSTERING_METHOD     = 1     (Scalable EM)
  MINIMUM_SUPPORT       = 1
  SAMPLE_SIZE           = 50000
  MAXIMUM_ITERATIONS    = 100
```

**6 Clusters kỳ vọng từ Food.com data:**
```
Cluster 1 — "High Protein & Fat"
  → Calories: cao (700+), Protein_PDV cao (>25), Fat cao
  → Ví dụ: Steak, Grilled Chicken, Eggs Benedict
  → Label: "Protein Powerhouse"

Cluster 2 — "Low Calorie, Light"
  → Calories thấp (<250), Fat thấp, Fiber nhiều
  → Ví dụ: Salads, Steamed Vegetables, Soups
  → Label: "Light & Fresh"

Cluster 3 — "High Carb Comfort"
  → Carbs_PDV cao (>40), Sugar cao, Calories trung bình-cao
  → Ví dụ: Pasta, Rice dishes, Bread, Pizza
  → Label: "Carb Heavy"

Cluster 4 — "Desserts & Sweets"
  → Sugar_PDV rất cao (>60), SatFat cao, Calories cao
  → Ví dụ: Cakes, Cookies, Ice Cream
  → Label: "Sweet Treats"

Cluster 5 — "Quick & Balanced"
  → Minutes thấp (≤30), Nutrition tương đối cân bằng
  → Ví dụ: Sandwiches, Wraps, Stir-fry
  → Label: "Quick & Easy"

Cluster 6 — "Slow Cook / Complex"
  → Minutes cao (>120), NSteps cao (>15), NIngredients nhiều
  → Ví dụ: Slow roasts, Stews, Multi-step bakes
  → Label: "Chef's Complex"
```

**Cập nhật ClusterID về Dim_Recipes:**
```sql
-- Chạy sau khi Mining Model đã được Process
UPDATE dr
SET
    dr.ClusterID    = CAST(REPLACE(mm.ClusterName, 'Cluster ', '') AS TINYINT),
    dr.ClusterLabel = CASE mm.ClusterName
                          WHEN 'Cluster 1' THEN 'Protein Powerhouse'
                          WHEN 'Cluster 2' THEN 'Light & Fresh'
                          WHEN 'Cluster 3' THEN 'Carb Heavy'
                          WHEN 'Cluster 4' THEN 'Sweet Treats'
                          WHEN 'Cluster 5' THEN 'Quick & Easy'
                          WHEN 'Cluster 6' THEN 'Chef''s Complex'
                          ELSE 'Uncategorized'
                      END
FROM Dim_Recipes dr
JOIN (
    SELECT RecipeID, $Cluster AS ClusterName
    FROM NutritionClustering  -- Tên Mining Model
) mm ON dr.RecipeID = mm.RecipeID;
```

### 3.6 Data Mining — Association Rules (Bonus)

```
Algorithm: Microsoft Association Rules
Goal: Tìm các nguyên liệu thường xuất hiện cùng nhau
      và công thức có rating cao đi kèm nhau

Input Table: STG_Recipes (ingredients parsed)
Key Column:  RecipeID
Input:       Ingredients (từng ingredient = 1 item)
Predict:     HighRating (AvgRating >= 4)

Parameters:
  MINIMUM_SUPPORT     = 0.01  (xuất hiện ≥ 1% recipes)
  MINIMUM_PROBABILITY = 0.40  (confidence ≥ 40%)
  MAXIMUM_ITEMSET_SIZE = 4
```

---

## BƯỚC 4 — TRUY VẤN MDX (THEO FOODCOM CUBE)

### MDX Query 1 — Tổng Lượt Đánh Giá & Calo Trung Bình theo Tháng

```mdx
-- ================================================================
-- QUERY 1: Thống kê hoạt động theo tháng (dựa trên interaction date)
-- Kết quả: Số lượt review + Avg Rating + Avg Calories từng tháng
-- ================================================================
WITH
    MEMBER [Measures].[Avg Calories Display] AS
        IIF([Measures].[Interaction Count] = 0, NULL,
            [Measures].[Calories] / [Measures].[Interaction Count]
        ), FORMAT_STRING = "#,##0.0 kcal"

    MEMBER [Measures].[Avg Rating Display] AS
        IIF([Measures].[Interaction Count] = 0, NULL,
            [Measures].[Sum of Ratings] / [Measures].[Interaction Count]
        ), FORMAT_STRING = "0.00 ★"

    -- So sánh với tháng trước (MoM)
    MEMBER [Measures].[Interactions MoM Δ] AS
        [Measures].[Interaction Count]
        - ([Measures].[Interaction Count],
           ParallelPeriod([Dim Time].[Calendar].[Month], 1,
                          [Dim Time].[Calendar].CurrentMember)),
        FORMAT_STRING = "+#,##0;-#,##0;0"

SELECT
    {
        [Measures].[Interaction Count],
        [Measures].[Total Reviews],
        [Measures].[Review Rate %],
        [Measures].[Avg Calories Display],
        [Measures].[Avg Rating Display],
        [Measures].[Interactions MoM Δ]
    } ON COLUMNS,

    NON EMPTY
    ORDER(
        [Dim Time].[Calendar].[Month].Members,
        [Dim Time].[Calendar].CurrentMember.Name,
        ASC
    ) ON ROWS

FROM [FoodCom Nutrition Cube]

WHERE [Dim Time].[Calendar].[Year].&[2018]  -- Thay năm tuỳ ý

-- ================================================================
-- Biến thể: Xem trend theo năm, so sánh 3 năm liên tiếp
-- ================================================================
/*
SELECT
    { [Dim Time].[Calendar].[Year].&[2016],
      [Dim Time].[Calendar].[Year].&[2017],
      [Dim Time].[Calendar].[Year].&[2018] } ON COLUMNS,
    { [Measures].[Interaction Count],
      [Measures].[Avg Rating Display],
      [Measures].[Avg Calories Display] } ON ROWS
FROM [FoodCom Nutrition Cube]
*/
```

### MDX Query 2 — Gợi ý Công Thức Dựa Trên Cluster

```mdx
-- ================================================================
-- QUERY 2: Gợi ý Top 10 công thức tốt nhất theo Cluster
-- Filter: Cluster "Light & Fresh" (Cluster 2) phù hợp giảm cân
-- ================================================================
WITH
    -- Composite Score: 50% Rating + 30% Nutrition Score + 20% Popularity
    MEMBER [Measures].[Recommendation Score] AS
        IIF(
            [Measures].[Interaction Count] = 0, NULL,
            (
                ([Measures].[Sum of Ratings] /
                    [Measures].[Interaction Count]) * 10 * 0.5
                +
                -- Popularity (interaction count normalized)
                ([Measures].[Interaction Count] /
                    MAX([Dim Recipes].[Recipe Name].Members,
                        [Measures].[Interaction Count])
                ) * 100 * 0.2
                +
                -- Thưởng cho recipe low calorie + high protein
                IIF([Dim Recipes].[Is Low Calorie].CurrentMember.Name = "1", 15, 0) +
                IIF([Dim Recipes].[Is High Protein].CurrentMember.Name = "1", 15, 0)
            )
        ), FORMAT_STRING = "#0.0"

    -- Label thân thiện cho Cluster
    MEMBER [Measures].[Cluster Name] AS
        [Dim Recipes].[Cluster Label].CurrentMember.Name

SELECT
    {
        [Measures].[Avg Calories],
        [Measures].[Protein Ratio %],
        [Measures].[Carb Ratio %],
        [Measures].[Fat Ratio %],
        [Measures].[Avg Rating],
        [Measures].[Interaction Count],
        [Measures].[Recommendation Score],
        [Measures].[Cluster Name]
    } ON COLUMNS,

    -- Top 10 công thức trong Cluster "Light & Fresh"
    NON EMPTY
    TOPCOUNT(
        FILTER(
            [Dim Recipes].[Recipe Name].Members,
            [Dim Recipes].[Cluster Label].CurrentMember.Name = "Light & Fresh"
            AND [Measures].[Avg Calories] < 400
            AND [Measures].[Interaction Count] >= 5
        ),
        10,
        [Measures].[Recommendation Score]
    ) ON ROWS

FROM [FoodCom Nutrition Cube]

-- ================================================================
-- Biến thể: Gợi ý theo mục tiêu người dùng cụ thể
-- ================================================================
/*
-- Cho người muốn tăng cơ bắp (Protein cao)
SELECT
    { [Measures].[Avg Calories], [Measures].[Protein Ratio %],
      [Measures].[Avg Rating], [Measures].[Recommendation Score] } ON COLUMNS,
    TOPCOUNT(
        FILTER(
            [Dim Recipes].[Recipe Name].Members,
            [Dim Recipes].[Is High Protein].CurrentMember.Name = "1"
            AND [Measures].[Protein Ratio %] > 25
        ),
        5,
        [Measures].[Recommendation Score]
    ) ON ROWS
FROM [FoodCom Nutrition Cube]
*/
```

### MDX Query 3 — Phân Tích Tỷ Lệ Macros theo Cluster

```mdx
-- ================================================================
-- QUERY 3: So sánh cân bằng Macronutrients giữa các Cluster
-- Kết quả: Ma trận Cluster × Macro ratios + WHO evaluation
-- ================================================================
WITH
    -- === Macro Ratios (tính từ gram/calo) ===
    MEMBER [Measures].[Protein % of Calories] AS
        IIF([Measures].[Avg Calories] = 0 OR [Measures].[Avg Calories] IS NULL,
            NULL,
            ([Measures].[Protein_PDV] / [Measures].[Interaction Count])
            * 50.0 / 100 * 4.0
            / ([Measures].[Calories] / [Measures].[Interaction Count]) * 100
        ), FORMAT_STRING = "#0.0"

    MEMBER [Measures].[Carb % of Calories] AS
        IIF([Measures].[Avg Calories] = 0 OR [Measures].[Avg Calories] IS NULL,
            NULL,
            ([Measures].[Carbs_PDV] / [Measures].[Interaction Count])
            * 275.0 / 100 * 4.0
            / ([Measures].[Calories] / [Measures].[Interaction Count]) * 100
        ), FORMAT_STRING = "#0.0"

    MEMBER [Measures].[Fat % of Calories] AS
        IIF([Measures].[Avg Calories] = 0 OR [Measures].[Avg Calories] IS NULL,
            NULL,
            ([Measures].[Total Fat_PDV] / [Measures].[Interaction Count])
            * 78.0 / 100 * 9.0
            / ([Measures].[Calories] / [Measures].[Interaction Count]) * 100
        ), FORMAT_STRING = "#0.0"

    -- === WHO Guideline Check ===
    -- WHO: Protein 10-35%, Carbs 45-65%, Fat 20-35%
    MEMBER [Measures].[WHO Protein] AS
        CASE
            WHEN [Measures].[Protein % of Calories] < 10  THEN "❌ Thiếu"
            WHEN [Measures].[Protein % of Calories] <= 35 THEN "✅ Đạt"
            ELSE "⚠️ Thừa"
        END

    MEMBER [Measures].[WHO Carb] AS
        CASE
            WHEN [Measures].[Carb % of Calories] < 45  THEN "❌ Thiếu"
            WHEN [Measures].[Carb % of Calories] <= 65 THEN "✅ Đạt"
            ELSE "⚠️ Thừa"
        END

    MEMBER [Measures].[WHO Fat] AS
        CASE
            WHEN [Measures].[Fat % of Calories] < 20  THEN "❌ Thiếu"
            WHEN [Measures].[Fat % of Calories] <= 35 THEN "✅ Đạt"
            ELSE "⚠️ Thừa"
        END

    -- === Balance Score 0-100 ===
    MEMBER [Measures].[Balance Score] AS
        NVL(
            IIF([Measures].[Protein % of Calories] >= 10
                AND [Measures].[Protein % of Calories] <= 35, 33, 0)
            + IIF([Measures].[Carb % of Calories] >= 45
                AND [Measures].[Carb % of Calories] <= 65, 34, 0)
            + IIF([Measures].[Fat % of Calories] >= 20
                AND [Measures].[Fat % of Calories] <= 35, 33, 0),
            0
        ), FORMAT_STRING = "#0"

    -- === Sugar & Sodium flags ===
    MEMBER [Measures].[Avg Sugar PDV] AS
        IIF([Measures].[Interaction Count] = 0, NULL,
            [Measures].[Sugar_PDV] / [Measures].[Interaction Count]
        ), FORMAT_STRING = "#0.0"

    MEMBER [Measures].[Avg Sodium PDV] AS
        IIF([Measures].[Interaction Count] = 0, NULL,
            [Measures].[Sodium_PDV] / [Measures].[Interaction Count]
        ), FORMAT_STRING = "#0.0"

SELECT
    {
        [Measures].[Avg Calories],
        [Measures].[Protein % of Calories],
        [Measures].[Carb % of Calories],
        [Measures].[Fat % of Calories],
        [Measures].[WHO Protein],
        [Measures].[WHO Carb],
        [Measures].[WHO Fat],
        [Measures].[Balance Score],
        [Measures].[Avg Sugar PDV],
        [Measures].[Avg Sodium PDV],
        [Measures].[Avg Rating],
        [Measures].[Interaction Count]
    } ON COLUMNS,

    -- Phân tích theo từng Cluster
    NON EMPTY
    ORDER(
        [Dim Recipes].[Cluster Label].Members,
        [Measures].[Balance Score],
        BDESC
    ) ON ROWS

FROM [FoodCom Nutrition Cube]

-- Tuỳ chọn: lọc theo năm gần nhất
-- WHERE [Dim Time].[Calendar].[Year].&[2018]

-- ================================================================
-- Biến thể: Pivot Cluster × Thời gian — xem thay đổi trend
-- ================================================================
/*
SELECT
    [Dim Time].[Calendar].[Year].Members ON COLUMNS,
    NON EMPTY
    CROSSJOIN(
        [Dim Recipes].[Cluster Label].Members,
        { [Measures].[Balance Score], [Measures].[Avg Calories] }
    ) ON ROWS
FROM [FoodCom Nutrition Cube]
*/
```

---

## BƯỚC 5 — TÍCH HỢP WEB (ASP.NET CORE + FOODCOM DATA)

### 5.1 Data Transfer Objects khớp với FoodCom schema

```csharp
// Models/Dtos.cs

public class RecipeDto
{
    public int     RecipeID       { get; set; }
    public string  RecipeName     { get; set; }
    public int     Minutes        { get; set; }
    public int     NSteps         { get; set; }
    public int     NIngredients   { get; set; }
    public decimal Calories       { get; set; }
    public decimal Protein_PDV    { get; set; }
    public decimal Carbs_PDV      { get; set; }
    public decimal TotalFat_PDV   { get; set; }
    public decimal Sugar_PDV      { get; set; }
    public decimal Sodium_PDV     { get; set; }
    // Computed (gram values)
    public decimal Protein_g      => Protein_PDV   * 50.0m  / 100;
    public decimal Carbs_g        => Carbs_PDV     * 275.0m / 100;
    public decimal TotalFat_g     => TotalFat_PDV  * 78.0m  / 100;
    public decimal Sugar_g        => Sugar_PDV     * 50.0m  / 100;
    public decimal Sodium_mg      => Sodium_PDV    * 2300.0m/ 100;
    // Macro ratios
    public decimal ProteinRatio   => Calories > 0 ? Protein_g * 4.0m / Calories * 100 : 0;
    public decimal CarbRatio      => Calories > 0 ? Carbs_g   * 4.0m / Calories * 100 : 0;
    public decimal FatRatio       => Calories > 0 ? TotalFat_g* 9.0m / Calories * 100 : 0;
    // Metadata
    public decimal AvgRating      { get; set; }
    public int     RatingCount    { get; set; }
    public int?    ClusterID      { get; set; }
    public string? ClusterLabel   { get; set; }
    public string? Tags_Raw       { get; set; }
    // Convenience
    public List<string> TagsList =>
        Tags_Raw?.Trim('[', ']')
                 .Split(',')
                 .Select(t => t.Trim().Trim('\''))
                 .ToList() ?? new();
}

public class InteractionSummaryDto
{
    public string MonthName       { get; set; }
    public int    Year            { get; set; }
    public int    Month           { get; set; }
    public long   InteractionCount{ get; set; }
    public int    TotalReviews    { get; set; }
    public decimal AvgRating      { get; set; }
    public decimal AvgCalories    { get; set; }
    public decimal AvgProtein_PDV { get; set; }
}

public class ClusterSummaryDto
{
    public int     ClusterID      { get; set; }
    public string  ClusterLabel   { get; set; }
    public int     RecipeCount    { get; set; }
    public decimal AvgCalories    { get; set; }
    public decimal AvgProtein_PDV { get; set; }
    public decimal AvgCarbs_PDV   { get; set; }
    public decimal AvgFat_PDV     { get; set; }
    public decimal AvgRating      { get; set; }
    public decimal BalanceScore   { get; set; }
}
```

### 5.2 Repository — SQL Server (FoodCom specific)

```csharp
// Infrastructure/FoodComSqlRepository.cs
public class FoodComSqlRepository : IFoodComRepository
{
    private readonly string _conn;
    public FoodComSqlRepository(IConfiguration config)
        => _conn = config.GetConnectionString("SqlServer");

    // Lấy summary theo tháng (từ Fact + Dim_Time)
    public async Task<IEnumerable<InteractionSummaryDto>> GetMonthlySummaryAsync(int year)
    {
        const string sql = """
            SELECT
                t.MonthName,
                t.[Year],
                t.[Month],
                COUNT(*)              AS InteractionCount,
                SUM(f.HasReview)      AS TotalReviews,
                AVG(CAST(f.Rating AS FLOAT))    AS AvgRating,
                AVG(f.Calories)       AS AvgCalories,
                AVG(f.Protein_PDV)    AS AvgProtein_PDV
            FROM Fact_RecipeInteraction f
            JOIN Dim_Time t ON f.TimeKey = t.TimeKey
            WHERE t.[Year] = @Year
            GROUP BY t.MonthName, t.[Year], t.[Month]
            ORDER BY t.[Month];
            """;
        await using var conn = new SqlConnection(_conn);
        return await conn.QueryAsync<InteractionSummaryDto>(sql, new { Year = year });
    }

    // Gợi ý recipe theo ClusterID, lọc theo nutritional constraints
    public async Task<IEnumerable<RecipeDto>> GetRecommendationsAsync(
        int clusterId,
        decimal maxCalories = 9999,
        decimal minProteinPDV = 0,
        int topN = 10)
    {
        const string sql = """
            SELECT TOP (@TopN)
                r.RecipeID, r.RecipeName, r.Minutes, r.NSteps,
                r.NIngredients, r.Calories, r.Protein_PDV, r.Carbs_PDV,
                r.TotalFat_PDV, r.Sugar_PDV, r.Sodium_PDV, r.SatFat_PDV,
                r.AvgRating, r.RatingCount, r.ClusterID, r.ClusterLabel,
                r.Tags_Raw
            FROM Dim_Recipes r
            WHERE r.ClusterID      = @ClusterId
              AND r.IsActive       = 1
              AND r.Calories       <= @MaxCalories
              AND r.Protein_PDV    >= @MinProteinPDV
              AND r.RatingCount    >= 3
            ORDER BY r.AvgRating DESC, r.RatingCount DESC;
            """;
        await using var conn = new SqlConnection(_conn);
        return await conn.QueryAsync<RecipeDto>(sql, new
        {
            ClusterId = clusterId,
            MaxCalories = maxCalories,
            MinProteinPDV = minProteinPDV,
            TopN = topN
        });
    }

    // Cluster summary — dùng cho Dashboard overview
    public async Task<IEnumerable<ClusterSummaryDto>> GetClusterSummaryAsync()
    {
        const string sql = """
            SELECT
                r.ClusterID,
                r.ClusterLabel,
                COUNT(*)          AS RecipeCount,
                AVG(r.Calories)   AS AvgCalories,
                AVG(r.Protein_PDV)AS AvgProtein_PDV,
                AVG(r.Carbs_PDV)  AS AvgCarbs_PDV,
                AVG(r.TotalFat_PDV)AS AvgFat_PDV,
                AVG(r.AvgRating)  AS AvgRating,
                -- Balance score
                AVG(
                    CASE WHEN r.Protein_PDV BETWEEN 10 AND 40 THEN 33 ELSE 0 END +
                    CASE WHEN r.Carbs_PDV   BETWEEN 20 AND 60 THEN 34 ELSE 0 END +
                    CASE WHEN r.TotalFat_PDV < 30             THEN 33 ELSE 0 END
                ) AS BalanceScore
            FROM Dim_Recipes r
            WHERE r.ClusterID IS NOT NULL AND r.IsActive = 1
            GROUP BY r.ClusterID, r.ClusterLabel
            ORDER BY r.ClusterID;
            """;
        await using var conn = new SqlConnection(_conn);
        return await conn.QueryAsync<ClusterSummaryDto>(sql);
    }

    // Full-text search recipe by name or ingredients
    public async Task<IEnumerable<RecipeDto>> SearchRecipesAsync(
        string keyword, decimal maxCalories = 9999, int topN = 20)
    {
        const string sql = """
            SELECT TOP (@TopN)
                r.RecipeID, r.RecipeName, r.Minutes, r.NSteps,
                r.NIngredients, r.Calories, r.Protein_PDV, r.Carbs_PDV,
                r.TotalFat_PDV, r.Sugar_PDV, r.Sodium_PDV,
                r.AvgRating, r.RatingCount, r.ClusterID, r.ClusterLabel, r.Tags_Raw
            FROM Dim_Recipes r
            WHERE (r.RecipeName      LIKE '%' + @Keyword + '%'
                OR r.Ingredients_Raw LIKE '%' + @Keyword + '%'
                OR r.Tags_Raw        LIKE '%' + @Keyword + '%')
              AND r.Calories <= @MaxCalories
              AND r.IsActive = 1
            ORDER BY r.AvgRating DESC, r.RatingCount DESC;
            """;
        await using var conn = new SqlConnection(_conn);
        return await conn.QueryAsync<RecipeDto>(sql,
            new { Keyword = keyword, MaxCalories = maxCalories, TopN = topN });
    }
}
```

### 5.3 API Controller

```csharp
// Controllers/NutritionApiController.cs
[ApiController]
[Route("api/v1/[controller]")]
public class NutritionController : ControllerBase
{
    private readonly IFoodComRepository _repo;
    private readonly ISsasRepository    _ssas;

    public NutritionController(IFoodComRepository repo, ISsasRepository ssas)
    {
        _repo = repo;
        _ssas = ssas;
    }

    // GET api/v1/nutrition/monthly?year=2018
    [HttpGet("monthly")]
    public async Task<IActionResult> GetMonthlySummary([FromQuery] int year = 2018)
    {
        var data = await _repo.GetMonthlySummaryAsync(year);
        return Ok(new { success = true, year, data });
    }

    // GET api/v1/nutrition/clusters
    [HttpGet("clusters")]
    public async Task<IActionResult> GetClusters()
    {
        var data = await _repo.GetClusterSummaryAsync();
        return Ok(new { success = true, data });
    }

    // GET api/v1/nutrition/recommend?clusterId=2&maxCalories=400&minProtein=10&top=10
    [HttpGet("recommend")]
    public async Task<IActionResult> GetRecommendations(
        [FromQuery] int     clusterId    = 2,
        [FromQuery] decimal maxCalories  = 9999,
        [FromQuery] decimal minProtein   = 0,
        [FromQuery] int     top          = 10)
    {
        var data = await _repo.GetRecommendationsAsync(
            clusterId, maxCalories, minProtein, top);
        return Ok(new { success = true, clusterId, data });
    }

    // GET api/v1/nutrition/search?q=chicken&maxCal=500
    [HttpGet("search")]
    public async Task<IActionResult> Search(
        [FromQuery] string  q      = "",
        [FromQuery] decimal maxCal = 9999)
    {
        if (string.IsNullOrWhiteSpace(q))
            return BadRequest(new { message = "Search keyword is required" });

        var data = await _repo.SearchRecipesAsync(q, maxCal);
        return Ok(new { success = true, query = q, count = data.Count(), data });
    }
}
```

### 5.4 Dashboard View (Frontend — Chart.js)

```html
<!-- Views/Home/Dashboard.cshtml -->
@{ ViewData["Title"] = "🥗 FoodCom Nutrition BI Dashboard"; }
<div class="container-fluid py-4">

    <!-- KPI Row -->
    <div class="row mb-4">
        <div class="col-md-3">
            <div class="card bg-primary text-white">
                <div class="card-body text-center">
                    <div class="fs-2 fw-bold" id="kpi-total-recipes">--</div>
                    <div>Total Recipes</div>
                    <small>Food.com dataset</small>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-success text-white">
                <div class="card-body text-center">
                    <div class="fs-2 fw-bold" id="kpi-total-interactions">--</div>
                    <div>Total Interactions</div>
                    <small>Ratings + Reviews</small>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-warning text-white">
                <div class="card-body text-center">
                    <div class="fs-2 fw-bold" id="kpi-avg-rating">--</div>
                    <div>Platform Avg Rating</div>
                    <small>★ out of 5</small>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-info text-white">
                <div class="card-body text-center">
                    <div class="fs-2 fw-bold">6</div>
                    <div>Recipe Clusters</div>
                    <small>AI Clustering (SSAS)</small>
                </div>
            </div>
        </div>
    </div>

    <!-- Charts Row -->
    <div class="row mb-4">
        <!-- Monthly Interactions Line Chart -->
        <div class="col-md-7">
            <div class="card">
                <div class="card-header d-flex justify-content-between align-items-center">
                    <span>📅 Monthly Interactions & Avg Rating</span>
                    <select id="yearSelect" class="form-select form-select-sm w-auto"
                            onchange="loadMonthlyData()">
                        <option value="2018">2018</option>
                        <option value="2017">2017</option>
                        <option value="2016">2016</option>
                        <option value="2015">2015</option>
                    </select>
                </div>
                <div class="card-body">
                    <canvas id="monthlyChart" height="90"></canvas>
                </div>
            </div>
        </div>
        <!-- Cluster Radar Chart -->
        <div class="col-md-5">
            <div class="card">
                <div class="card-header">🤖 Cluster Nutrition Profile (Radar)</div>
                <div class="card-body">
                    <canvas id="clusterRadar" height="200"></canvas>
                </div>
            </div>
        </div>
    </div>

    <!-- Recipe Recommendation Row -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header">
                    <div class="d-flex gap-2 align-items-center flex-wrap">
                        <span>🍽️ Smart Recipe Recommendations</span>
                        <select id="clusterSelect" class="form-select form-select-sm w-auto">
                            <option value="2">🥗 Light & Fresh (giảm cân)</option>
                            <option value="1">💪 Protein Powerhouse (tăng cơ)</option>
                            <option value="5">⚡ Quick & Easy (bận rộn)</option>
                            <option value="3">🍝 Carb Heavy (năng lượng)</option>
                            <option value="4">🍰 Sweet Treats (tráng miệng)</option>
                            <option value="6">👨‍🍳 Chef's Complex (đầu bếp)</option>
                        </select>
                        <input type="number" id="maxCalInput" class="form-control form-control-sm w-auto"
                               placeholder="Max kcal" value="9999">
                        <button class="btn btn-sm btn-primary" onclick="loadRecommendations()">
                            🔍 Get Recommendations
                        </button>
                        <!-- Search box -->
                        <input type="text" id="searchInput" class="form-control form-control-sm w-auto"
                               placeholder="Search ingredient...">
                        <button class="btn btn-sm btn-outline-secondary" onclick="searchRecipes()">
                            Search
                        </button>
                    </div>
                </div>
                <div class="card-body">
                    <div id="recipe-cards" class="row g-3"></div>
                </div>
            </div>
        </div>
    </div>
</div>

@section Scripts {
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
let monthlyChart, clusterChart;

// ==============================================================
// MONTHLY CHART (Line + Bar combo)
// ==============================================================
async function loadMonthlyData() {
    const year = document.getElementById('yearSelect').value;
    const r = await fetch(`/api/v1/nutrition/monthly?year=${year}`);
    const j = await r.json();

    const labels       = j.data.map(d => d.monthName.substring(0,3));
    const interactions = j.data.map(d => d.interactionCount);
    const avgRatings   = j.data.map(d => parseFloat(d.avgRating).toFixed(2));
    const avgCalories  = j.data.map(d => parseFloat(d.avgCalories).toFixed(0));

    if (monthlyChart) monthlyChart.destroy();
    monthlyChart = new Chart(document.getElementById('monthlyChart'), {
        data: {
            labels,
            datasets: [
                {
                    type: 'bar',
                    label: 'Interactions',
                    data: interactions,
                    backgroundColor: 'rgba(54,162,235,0.6)',
                    yAxisID: 'y'
                },
                {
                    type: 'line',
                    label: 'Avg Rating ★',
                    data: avgRatings,
                    borderColor: '#ff6384',
                    backgroundColor: 'transparent',
                    tension: 0.4,
                    yAxisID: 'y1',
                    pointRadius: 4
                },
                {
                    type: 'line',
                    label: 'Avg Calories',
                    data: avgCalories,
                    borderColor: '#ffce56',
                    borderDash: [5,5],
                    backgroundColor: 'transparent',
                    tension: 0.3,
                    yAxisID: 'y2',
                    pointRadius: 3
                }
            ]
        },
        options: {
            responsive: true,
            scales: {
                y:  { type:'linear', position:'left',  title:{display:true, text:'Interactions'} },
                y1: { type:'linear', position:'right', min:0, max:5,
                      title:{display:true, text:'Avg Rating'}, grid:{drawOnChartArea:false} },
                y2: { type:'linear', position:'right', display:false,
                      grid:{drawOnChartArea:false} }
            },
            plugins: { legend: { position: 'top' } }
        }
    });
}

// ==============================================================
// CLUSTER RADAR CHART
// ==============================================================
async function loadClusterChart() {
    const r = await fetch('/api/v1/nutrition/clusters');
    const j = await r.json();

    const labels  = j.data.map(d => d.clusterLabel);
    const protein = j.data.map(d => parseFloat(d.avgProtein_PDV).toFixed(1));
    const carbs   = j.data.map(d => parseFloat(d.avgCarbs_PDV).toFixed(1));
    const fat     = j.data.map(d => parseFloat(d.avgFat_PDV).toFixed(1));
    const rating  = j.data.map(d => (parseFloat(d.avgRating)*20).toFixed(0)); // scale 0-100
    const balance = j.data.map(d => parseFloat(d.balanceScore).toFixed(0));

    if (clusterChart) clusterChart.destroy();
    clusterChart = new Chart(document.getElementById('clusterRadar'), {
        type: 'radar',
        data: {
            labels: ['Protein%', 'Carbs%', 'Fat%', 'Rating×20', 'Balance'],
            datasets: j.data.map((d, i) => ({
                label: d.clusterLabel,
                data: [protein[i], carbs[i], fat[i], rating[i], balance[i]],
                fill: true,
                backgroundColor: `hsla(${i*60},70%,60%,0.15)`,
                borderColor:     `hsl(${i*60},70%,45%)`,
                pointRadius: 3
            }))
        },
        options: {
            responsive: true,
            scales: { r: { min: 0, max: 100, ticks: { stepSize: 20 } } }
        }
    });
}

// ==============================================================
// RECIPE RECOMMENDATION CARDS
// ==============================================================
async function loadRecommendations() {
    const clusterId  = document.getElementById('clusterSelect').value;
    const maxCal     = document.getElementById('maxCalInput').value || 9999;
    const r = await fetch(
        `/api/v1/nutrition/recommend?clusterId=${clusterId}&maxCalories=${maxCal}&top=9`
    );
    const j = await r.json();
    renderRecipeCards(j.data);
}

async function searchRecipes() {
    const q      = document.getElementById('searchInput').value;
    const maxCal = document.getElementById('maxCalInput').value || 9999;
    if (!q.trim()) return;
    const r = await fetch(`/api/v1/nutrition/search?q=${encodeURIComponent(q)}&maxCal=${maxCal}`);
    const j = await r.json();
    renderRecipeCards(j.data);
}

function renderRecipeCards(recipes) {
    const grid = document.getElementById('recipe-cards');
    if (!recipes || recipes.length === 0) {
        grid.innerHTML = '<div class="col-12 text-center text-muted py-4">No recipes found.</div>';
        return;
    }
    grid.innerHTML = recipes.map(r => {
        const proteinRatio = r.calories > 0
            ? ((r.protein_g * 4 / r.calories) * 100).toFixed(0) : 0;
        const carbRatio    = r.calories > 0
            ? ((r.carbs_g   * 4 / r.calories) * 100).toFixed(0) : 0;
        const fatRatio     = r.calories > 0
            ? ((r.totalFat_g* 9 / r.calories) * 100).toFixed(0) : 0;

        const tags = (r.tags_Raw || '')
            .replace('[','').replace(']','')
            .split(',').slice(0,3)
            .map(t => `<span class="badge bg-light text-dark border me-1">${t.trim().replace(/'/g,'')}</span>`)
            .join('');

        return `
        <div class="col-md-4">
          <div class="card h-100 shadow-sm">
            <div class="card-body">
              <h6 class="card-title fw-bold text-capitalize">${r.recipeName}</h6>
              <div class="d-flex gap-2 mb-2">
                <span class="badge bg-warning text-dark">⭐ ${parseFloat(r.avgRating).toFixed(2)}</span>
                <span class="badge bg-secondary">⏱ ${r.minutes}m</span>
                <span class="badge bg-info">${r.nIngredients} ingr.</span>
                ${r.clusterLabel ? `<span class="badge bg-success">${r.clusterLabel}</span>` : ''}
              </div>
              <div class="row text-center border rounded p-2 mb-2 bg-light">
                <div class="col-3">
                  <div class="fw-bold">${Math.round(r.calories)}</div>
                  <small class="text-muted">kcal</small>
                </div>
                <div class="col-3">
                  <div class="fw-bold text-danger">${proteinRatio}%</div>
                  <small class="text-muted">Protein</small>
                </div>
                <div class="col-3">
                  <div class="fw-bold text-primary">${carbRatio}%</div>
                  <small class="text-muted">Carbs</small>
                </div>
                <div class="col-3">
                  <div class="fw-bold text-warning">${fatRatio}%</div>
                  <small class="text-muted">Fat</small>
                </div>
              </div>
              <div class="mt-1">${tags}</div>
            </div>
            <div class="card-footer text-muted small">
              ${r.ratingCount} ratings · ${r.nSteps} steps
            </div>
          </div>
        </div>`;
    }).join('');
}

// ==============================================================
// INIT
// ==============================================================
document.addEventListener('DOMContentLoaded', () => {
    loadMonthlyData();
    loadClusterChart();
    loadRecommendations();
});
</script>
}
```

---

## 📊 CHECKLIST TRIỂN KHAI ĐẦY ĐỦ

```
✅ Phase 0 – Chuẩn bị
  ☐ Tải RAW_recipes.csv + RAW_interactions.csv từ Kaggle
  ☐ Cài đặt: SQL Server, Visual Studio + SSDT, ASP.NET Core SDK 8

✅ Phase 1 – Database
  ☐ Tạo NutritionDW_FoodCom database
  ☐ Chạy DDL: Staging → Dim_Time → Dim_Recipes → Dim_Users → Fact
  ☐ Verify Foreign Keys và Indexes

✅ Phase 2 – SSIS ETL
  ☐ Tạo SSIS Project, Connection Managers (FF + OLEDB)
  ☐ Control Flow: 9 tasks theo đúng thứ tự
  ☐ DFT recipes: Flat File → Data Conversion → Split → Dim_Recipes
  ☐ DFT interactions: Flat File → Data Conversion → Split → STG
  ☐ SQL Task: Parse nutrition "[v1,v2,v3,v4,v5,v6,v7]"
  ☐ DFT Dim_Users: Aggregate per user_id
  ☐ DFT Fact: JOIN 3 Dims → Fact_RecipeInteraction
  ☐ SQL Task: Update AvgRating vào Dim_Recipes
  ☐ Test với 1000 rows → Full load

✅ Phase 3 – SSAS Cube
  ☐ SSAS Project + Data Source → DSV
  ☐ Dimensions: Time (với Calendar hierarchy), Recipes, Users
  ☐ Cube: Measures + Calculated Members (Avg Rating, Ratios, Score)
  ☐ KPI: Recipe Quality
  ☐ Mining Structure: NutritionClustering (6 clusters)
  ☐ Process Cube → Process Mining Model
  ☐ Cập nhật ClusterID + ClusterLabel → Dim_Recipes

✅ Phase 4 – MDX Validation
  ☐ Query 1 (Monthly summary) trong SQL Server Management Studio
  ☐ Query 2 (Cluster recommendations)
  ☐ Query 3 (Macro ratios × Cluster)

✅ Phase 5 – Web
  ☐ ASP.NET Core project + Dapper + ADOMD.NET
  ☐ DTOs khớp FoodCom schema (PDV → gram conversion logic)
  ☐ Repository: GetMonthlySummary, GetRecommendations, Search
  ☐ API endpoints: /monthly, /clusters, /recommend, /search
  ☐ Dashboard UI: combo chart, radar chart, recipe cards
  ☐ Test end-to-end
```

---

> 📌 **Mapping tóm tắt: Tên file CSV → Bảng trong SQL Server**
>
> | File CSV gốc | Đi vào Staging | Đi vào Dimension / Fact |
> |---|---|---|
> | `RAW_recipes.csv` | `STG_Recipes` | `Dim_Recipes` (sau parse nutrition) |
> | `RAW_interactions.csv` (aggregate) | `STG_Interactions` | `Dim_Users` |
> | JOIN cả hai | — | `Fact_RecipeInteraction` |
> | Cột `nutrition` (parse) | trong STG_Recipes | Cột con: Calories, TotalFat_PDV, Sugar_PDV, Sodium_PDV, Protein_PDV, SatFat_PDV, Carbs_PDV |
