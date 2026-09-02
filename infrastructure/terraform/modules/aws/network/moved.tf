moved {
  from = aws_vpc.main
  to   = aws_vpc.main["this"]
}

moved {
  from = aws_internet_gateway.main
  to   = aws_internet_gateway.main["this"]
}

moved {
  from = aws_subnet.management
  to   = aws_subnet.management["this"]
}

moved {
  from = aws_subnet.workload
  to   = aws_subnet.workload["this"]
}

moved {
  from = aws_eip.nat
  to   = aws_eip.nat["this"]
}

moved {
  from = aws_nat_gateway.main
  to   = aws_nat_gateway.main["this"]
}

moved {
  from = aws_route_table.management
  to   = aws_route_table.management["this"]
}

moved {
  from = aws_route.management_internet
  to   = aws_route.management_internet["this"]
}

moved {
  from = aws_route_table_association.management
  to   = aws_route_table_association.management["this"]
}

moved {
  from = aws_route_table.workload
  to   = aws_route_table.workload["this"]
}

moved {
  from = aws_route.workload_internet
  to   = aws_route.workload_internet["this"]
}

moved {
  from = aws_route_table_association.workload
  to   = aws_route_table_association.workload["this"]
}
