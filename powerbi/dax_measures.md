# DAX Measures — Power BI Model

All measures created in the `fact_orders` table.

## Core measures

```dax
Total Sales = SUM(fact_orders[Sales])
```

```dax
Total Profit = SUM(fact_orders[Order_Profit_Per_Order])
```

```dax
Total Orders = DISTINCTCOUNT(fact_orders[Order_Id])
```

```dax
Profit Margin % = DIVIDE([Total Profit], [Total Sales], 0)
```

## Shipping & delivery measures

```dax
Avg Days for Shipping = AVERAGE(fact_orders[Days_for_shipping_real])
```

```dax
Avg Days Scheduled = AVERAGE(fact_orders[Days_for_shipment_scheduled])
```

```dax
Shipping Delay (Days) = [Avg Days for Shipping] - [Avg Days Scheduled]
```

```dax
Late Delivery Rate % = 
DIVIDE(
    CALCULATE(COUNTROWS(fact_orders), fact_orders[Late_delivery_risk] = 1),
    COUNTROWS(fact_orders),
    0
)
```

## Role-playing dimension example

`fact_orders` has two relationships to `dim_date` (Order_Date_Id and Shipping_Date_Id).
Only one relationship can be active by default (Order_Date_Id). This measure explicitly
activates the inactive Shipping_Date_Id relationship using USERELATIONSHIP:

```dax
Total Sales by Shipping Date = 
CALCULATE(
    SUM(fact_orders[Sales]),
    USERELATIONSHIP(fact_orders[Shipping_Date_Id], dim_date[Date_Id])
)
```