#!/bin/bash
# 数字特征自动域提取示例

echo "=========================================="
echo "alphaFFM-go 数字特征自动域提取"
echo "=========================================="
echo ""

# 1. 展示特征编码规则
echo "1. 特征编码规则："
echo "   - 大数字特征（>= 2^32）: 高32位 = 域ID，低32位 = 特征ID"
echo "   - 小数字/字符特征: 使用配置文件映射"
echo ""

# 2. 解析示例特征
echo "2. 示例特征解析："
go run tools/extract_field_id.go | grep -A 50 "特征编码解析"
echo ""

# 3. 查看测试样本
echo "3. 测试样本（混合格式）："
head -4 test_data_numeric_field.txt | grep -v "^#"
echo ""

# 4. 查看配置文件
echo "4. 配置文件（仅配置小特征）："
cat field_config_numeric.txt | grep -v "^#" | grep -v "^$"
echo ""

# 5. 训练模型
echo "5. 训练模型..."
cat test_data_numeric_field.txt | ./bin/ffm_train \
    -m model_with_numeric.txt \
    -field_config field_config_numeric.txt \
    -dim 1,1,8 \
    -core 1 2>&1 | grep -E "Loaded|output"
echo ""

# 6. 查看模型中的域
echo "6. 模型中的域定义："
head -1 model_with_numeric.txt
echo ""
echo "   说明："
echo "   - field_12, field_13, field_14: 自动从大数字特征提取"
echo "   - user, item, context: 从配置文件映射"
echo ""

# 7. 预测
echo "7. 预测..."
cat test_data_numeric_field.txt | ./bin/ffm_predict \
    -m model_with_numeric.txt \
    -field_config field_config_numeric.txt \
    -dim 8 \
    -out predictions_numeric.txt \
    -core 1 2>&1 | grep -E "Loaded|loading"
echo ""

# 8. 查看预测结果
echo "8. 预测结果："
head -5 predictions_numeric.txt
echo ""

echo "=========================================="
echo "数字特征自动提取的优势："
echo "  1. 大数字特征自动提取域ID，无需配置"
echo "  2. 高32位编码域ID，支持海量域"
echo "  3. 小特征继续使用配置文件，灵活可控"
echo "  4. 完美支持业务中的特征编码规范"
echo "=========================================="

