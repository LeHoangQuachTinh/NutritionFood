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