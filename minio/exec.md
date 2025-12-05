aws --endpoint-url http://minio:9000 s3 mb s3://datalake

aws --endpoint-url http://minio:9000 s3api put-object --bucket datalake --key "bronze/"

aws --endpoint-url http://minio:9000 s3api put-object --bucket datalake --key "silver/"

aws --endpoint-url http://minio:9000 s3api put-object --bucket datalake --key "gold/"


printf "order_id,customer_id,amount\n1,1001,29.99\n2,1002,15.50\n" > orders.csv
aws --endpoint-url http://minio:9000 s3 cp orders.csv s3://datalake/bronze/sales/orders/orders.csv
aws --endpoint-url http://minio:9000 s3 cp orders.csv s3://datalake/bronze/sales/orders/year=2025/month=12/day=05/orders_0001.csv


aws --endpoint-url http://minio:9000 s3 ls
aws --endpoint-url http://minio:9000 s3 ls s3://datalake/ --recursive
aws --endpoint-url http://minio:9000 s3api head-object --bucket datalake --key "bronze/sales/orders/orders.csv"
aws --endpoint-url http://minio:9000 s3 cp s3://datalake/bronze/sales/orders/orders.csv s3://datalake/silver/sales/orders/orders_clean.csv
