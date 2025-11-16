#!/bin/zsh

DIR=ece493t31-f25
cp $DIR/labs-admin/lab2-sol/Makefile .
cp $DIR/labs-admin/lab2-sol/*.sh .
cp $DIR/labs-admin/lab2-sol/env.csh .

source env.sh

# 20
./grade_verilog.sh   > autograde.txt
# 40
./grade_asic.sh      >> autograde.txt
# 40
./grade_sta.sh       >> autograde.txt

cat autograde.txt | grep GRADE, > grade.csv
