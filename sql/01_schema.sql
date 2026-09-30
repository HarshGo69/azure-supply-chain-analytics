-- ============================================
-- 01_schema.sql
-- Creates staging table, 5 dimension tables, and fact table
-- ============================================

-- Staging table (raw 1:1 mirror of the CSV structure)
CREATE TABLE staging_orders (
    [Type] VARCHAR(50),
    [Days_for_shipping_real] INT,
    [Days_for_shipment_scheduled] INT,
    [Benefit_per_order] DECIMAL(18,4),
    [Sales_per_customer] DECIMAL(18,4),
    [Delivery_Status] VARCHAR(50),
    [Late_delivery_risk] INT,
    [Category_Id] INT,
    [Category_Name] VARCHAR(100),
    [Customer_City] VARCHAR(100),
    [Customer_Country] VARCHAR(100),
    [Customer_Email] VARCHAR(100),
    [Customer_Fname] VARCHAR(100),
    [Customer_Id] INT,
    [Customer_Lname] VARCHAR(100),
    [Customer_Password] VARCHAR(100),
    [Customer_Segment] VARCHAR(50),
    [Customer_State] VARCHAR(50),
    [Customer_Street] VARCHAR(200),
    [Customer_Zipcode] VARCHAR(20),
    [Department_Id] INT,
    [Department_Name] VARCHAR(100),
    [Latitude] DECIMAL(9,6),
    [Longitude] DECIMAL(9,6),
    [Market] VARCHAR(50),
    [Order_City] VARCHAR(100),
    [Order_Country] VARCHAR(100),
    [Order_Customer_Id] INT,
    [order_date] DATETIME,
    [Order_Id] INT,
    [Order_Item_Cardprod_Id] INT,
    [Order_Item_Discount] DECIMAL(18,4),
    [Order_Item_Discount_Rate] DECIMAL(9,4),
    [Order_Item_Id] INT,
    [Order_Item_Product_Price] DECIMAL(18,4),
    [Order_Item_Profit_Ratio] DECIMAL(9,4),
    [Order_Item_Quantity] INT,
    [Sales] DECIMAL(18,4),
    [Order_Item_Total] DECIMAL(18,4),
    [Order_Profit_Per_Order] DECIMAL(18,4),
    [Order_Region] VARCHAR(50),
    [Order_State] VARCHAR(50),
    [Order_Status] VARCHAR(50),
    [Order_Zipcode] VARCHAR(20),
    [Product_Card_Id] INT,
    [Product_Category_Id] INT,
    [Product_Description] VARCHAR(MAX),
    [Product_Image] VARCHAR(500),
    [Product_Name] VARCHAR(200),
    [Product_Price] DECIMAL(18,4),
    [Product_Status] INT,
    [shipping_date] DATETIME,
    [Shipping_Mode] VARCHAR(50)
);

-- Dimension: customers (Email and Password intentionally excluded from the model)
CREATE TABLE dim_customer (
    Customer_Id INT PRIMARY KEY,
    Customer_Fname VARCHAR(100),
    Customer_Lname VARCHAR(100),
    Customer_Segment VARCHAR(50),
    Customer_City VARCHAR(100),
    Customer_State VARCHAR(50),
    Customer_Street VARCHAR(200),
    Customer_Zipcode VARCHAR(20),
    Customer_Country VARCHAR(100)
);

-- Dimension: products
CREATE TABLE dim_product (
    Product_Card_Id INT PRIMARY KEY,
    Product_Name VARCHAR(200),
    Product_Price DECIMAL(18,4),
    Product_Status INT,
    Category_Id INT,
    Category_Name VARCHAR(100),
    Department_Id INT,
    Department_Name VARCHAR(100)
);

-- Dimension: date (role-playing dimension, reused for both order date and shipping date)
CREATE TABLE dim_date (
    Date_Id INT IDENTITY(1,1) PRIMARY KEY,
    [Date] DATE UNIQUE,
    [Year] INT,
    [Quarter] INT,
    [Month] INT,
    [MonthName] VARCHAR(20),
    [Day] INT,
    [Weekday] VARCHAR(20)
);

-- Dimension: geography
CREATE TABLE dim_geography (
    Geography_Id INT IDENTITY(1,1) PRIMARY KEY,
    Order_City VARCHAR(100),
    Order_State VARCHAR(50),
    Order_Country VARCHAR(100),
    Order_Region VARCHAR(50),
    Market VARCHAR(50),
    Latitude DECIMAL(9,6),
    Longitude DECIMAL(9,6)
);

-- Dimension: shipping
CREATE TABLE dim_shipping (
    Shipping_Id INT IDENTITY(1,1) PRIMARY KEY,
    Shipping_Mode VARCHAR(50),
    Delivery_Status VARCHAR(50)
);

-- Fact table: one row per order line item, with FKs to all 5 dimensions
CREATE TABLE fact_orders (
    Order_Item_Id INT PRIMARY KEY,
    Order_Id INT,
    Customer_Id INT FOREIGN KEY REFERENCES dim_customer(Customer_Id),
    Product_Card_Id INT FOREIGN KEY REFERENCES dim_product(Product_Card_Id),
    Order_Date_Id INT FOREIGN KEY REFERENCES dim_date(Date_Id),
    Shipping_Date_Id INT FOREIGN KEY REFERENCES dim_date(Date_Id),
    Geography_Id INT FOREIGN KEY REFERENCES dim_geography(Geography_Id),
    Shipping_Id INT FOREIGN KEY REFERENCES dim_shipping(Shipping_Id),
    Days_for_shipping_real INT,
    Days_for_shipment_scheduled INT,
    Late_delivery_risk INT,
    Order_Item_Discount DECIMAL(18,4),
    Order_Item_Discount_Rate DECIMAL(9,4),
    Order_Item_Product_Price DECIMAL(18,4),
    Order_Item_Profit_Ratio DECIMAL(9,4),
    Order_Item_Quantity INT,
    Sales DECIMAL(18,4),
    Order_Item_Total DECIMAL(18,4),
    Order_Profit_Per_Order DECIMAL(18,4),
    Benefit_per_order DECIMAL(18,4),
    Sales_per_customer DECIMAL(18,4),
    Order_Status VARCHAR(50)
);