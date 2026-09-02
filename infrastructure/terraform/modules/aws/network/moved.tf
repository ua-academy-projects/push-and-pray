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

moved {
  from = aws_vpc.main["this"]
  to   = aws_vpc.main["europe"]
}

moved {
  from = aws_internet_gateway.main["this"]
  to   = aws_internet_gateway.main["europe"]
}

moved {
  from = aws_subnet.management["this"]
  to   = aws_subnet.management["europe"]
}

moved {
  from = aws_subnet.workload["this"]
  to   = aws_subnet.workload["europe"]
}

moved {
  from = aws_eip.nat["this"]
  to   = aws_eip.nat["europe"]
}

moved {
  from = aws_nat_gateway.main["this"]
  to   = aws_nat_gateway.main["europe"]
}

moved {
  from = aws_route_table.management["this"]
  to   = aws_route_table.management["europe"]
}

moved {
  from = aws_route.management_internet["this"]
  to   = aws_route.management_internet["europe"]
}

moved {
  from = aws_route_table_association.management["this"]
  to   = aws_route_table_association.management["europe"]
}

moved {
  from = aws_route_table.workload["this"]
  to   = aws_route_table.workload["europe"]
}

moved {
  from = aws_route.workload_internet["this"]
  to   = aws_route.workload_internet["europe"]
}

moved {
  from = aws_route_table_association.workload["this"]
  to   = aws_route_table_association.workload["europe"]
}
