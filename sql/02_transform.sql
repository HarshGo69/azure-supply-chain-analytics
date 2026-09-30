-- ============================================
-- 02_transform.sql
-- Populates dimensions and fact table from staging
-- ============================================

-- dim_customer
INSERT INTO dim_customer (Customer_Id, Customer_Fname, Customer_Lname, Customer_Segment, 
    Customer_City, Customer_State, Customer_Street, Customer_Zipcode, Customer_Country)
SELECT DISTINCT
    Customer_Id, Customer_Fname, Customer_Lname, Customer_Segment,
    Customer_City, Customer_State, Customer_Street, Customer_Zipcode, Customer_Country
FROM staging_orders s
WHERE Customer_Id IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.Customer_Id = s.Customer_Id);

-- dim_product
INSERT INTO dim_product (Product_Card_Id, Product_Name, Product_Price, Product_Status,
    Category_Id, Category_Name, Department_Id, Department_Name)
SELECT DISTINCT
    Product_Card_Id, Product_Name, Product_Price, Product_Status,
    Category_Id, Category_Name, Department_Id, Department_Name
FROM staging_orders s
WHERE Product_Card_Id IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM dim_product d WHERE d.Product_Card_Id = s.Product_Card_Id);

-- dim_shipping
INSERT INTO dim_shipping (Shipping_Mode, Delivery_Status)
SELECT DISTINCT Shipping_Mode, Delivery_Status
FROM staging_orders
WHERE Shipping_Mode IS NOT NULL;

-- dim_geography
-- Note: initial attempt deduped including lat/long, producing 64,867 rows
-- instead of the correct ~3,772. Fixed by grouping only on categorical fields
-- and using MIN() to pick one representative coordinate per location.
INSERT INTO dim_geography (Order_City, Order_State, Order_Country, Order_Region, Market, Latitude, Longitude)
SELECT Order_City, Order_State, Order_Country, Order_Region, Market, 
    MIN(Latitude) AS Latitude, MIN(Longitude) AS Longitude
FROM staging_orders
WHERE Order_City IS NOT NULL
GROUP BY Order_City, Order_State, Order_Country, Order_Region, Market;

-- dim_date (built from both order dates and shipping dates combined)
INSERT INTO dim_date ([Date], [Year], [Quarter], [Month], [MonthName], [Day], [Weekday])
SELECT DISTINCT
    CAST(dt AS DATE) AS [Date],
    YEAR(dt) AS [Year],
    DATEPART(QUARTER, dt) AS [Quarter],
    MONTH(dt) AS [Month],
    DATENAME(MONTH, dt) AS [MonthName],
    DAY(dt) AS [Day],
    DATENAME(WEEKDAY, dt) AS [Weekday]
FROM (
    SELECT order_date AS dt FROM staging_orders WHERE order_date IS NOT NULL
    UNION
    SELECT shipping_date AS dt FROM staging_orders WHERE shipping_date IS NOT NULL
) AS combined_dates;

-- fact_orders (joins staging back to all 5 dimensions)
INSERT INTO fact_orders (
    Order_Item_Id, Order_Id, Customer_Id, Product_Card_Id, 
    Order_Date_Id, Shipping_Date_Id, Geography_Id, Shipping_Id,
    Days_for_shipping_real, Days_for_shipment_scheduled, Late_delivery_risk,
    Order_Item_Discount, Order_Item_Discount_Rate, Order_Item_Product_Price,
    Order_Item_Profit_Ratio, Order_Item_Quantity, Sales, Order_Item_Total,
    Order_Profit_Per_Order, Benefit_per_order, Sales_per_customer, Order_Status
)
SELECT
    s.Order_Item_Id, s.Order_Id, s.Customer_Id, s.Product_Card_Id,
    od.Date_Id AS Order_Date_Id,
    sd.Date_Id AS Shipping_Date_Id,
    g.Geography_Id,
    sh.Shipping_Id,
    s.Days_for_shipping_real, s.Days_for_shipment_scheduled, s.Late_delivery_risk,
    s.Order_Item_Discount, s.Order_Item_Discount_Rate, s.Order_Item_Product_Price,
    s.Order_Item_Profit_Ratio, s.Order_Item_Quantity, s.Sales, s.Order_Item_Total,
    s.Order_Profit_Per_Order, s.Benefit_per_order, s.Sales_per_customer, s.Order_Status
FROM staging_orders s
LEFT JOIN dim_date od ON CAST(s.order_date AS DATE) = od.[Date]
LEFT JOIN dim_date sd ON CAST(s.shipping_date AS DATE) = sd.[Date]
LEFT JOIN dim_geography g ON s.Order_City = g.Order_City 
    AND s.Order_State = g.Order_State 
    AND s.Order_Country = g.Order_Country
    AND s.Order_Region = g.Order_Region
    AND s.Market = g.Market
LEFT JOIN dim_shipping sh ON s.Shipping_Mode = sh.Shipping_Mode 
    AND s.Delivery_Status = sh.Delivery_Status
WHERE NOT EXISTS (SELECT 1 FROM fact_orders f WHERE f.Order_Item_Id = s.Order_Item_Id);