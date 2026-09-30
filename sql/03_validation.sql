-- ============================================
-- 03_validation.sql
-- Data quality checks and reusable validation procedure
-- ============================================

CREATE TABLE staging_rejects (
    Reject_Id INT IDENTITY(1,1) PRIMARY KEY,
    Order_Item_Id INT,
    Reject_Reason VARCHAR(200),
    Rejected_At DATETIME DEFAULT GETDATE()
);

-- One-time validation check (ran clean: 0 rejected rows)
INSERT INTO staging_rejects (Order_Item_Id, Reject_Reason)
SELECT Order_Item_Id, 'Missing Customer_Id'
FROM staging_orders WHERE Customer_Id IS NULL

UNION ALL

SELECT Order_Item_Id, 'Missing Product_Card_Id'
FROM staging_orders WHERE Product_Card_Id IS NULL

UNION ALL

SELECT Order_Item_Id, 'Negative or zero quantity'
FROM staging_orders WHERE Order_Item_Quantity <= 0

UNION ALL

SELECT Order_Item_Id, 'Order date after shipping date (logically invalid)'
FROM staging_orders WHERE order_date > shipping_date

UNION ALL

SELECT Order_Item_Id, 'Negative sales value'
FROM staging_orders WHERE Sales < 0;

-- Reusable stored procedure for validating future data loads
CREATE PROCEDURE sp_ValidateStagingData
AS
BEGIN
    INSERT INTO staging_rejects (Order_Item_Id, Reject_Reason)
    SELECT Order_Item_Id, 'Missing Customer_Id'
    FROM staging_orders WHERE Customer_Id IS NULL
    AND Order_Item_Id NOT IN (SELECT Order_Item_Id FROM staging_rejects)

    UNION ALL

    SELECT Order_Item_Id, 'Negative or zero quantity'
    FROM staging_orders WHERE Order_Item_Quantity <= 0
    AND Order_Item_Id NOT IN (SELECT Order_Item_Id FROM staging_rejects);
END;