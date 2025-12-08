#!/bin/bash
# FM格式样本使用配置文件的完整示例

echo "=========================================="
echo "alphaFFM-go 配置文件模式示例"
echo "=========================================="
echo ""

# 1. 准备配置文件
echo "1. 创建配置文件 (field_config_test.txt):"
cat field_config_test.txt
echo ""

# 2. 准备FM格式样本
echo "2. 查看FM格式样本 (前3行):"
head -3 test_data_fm.txt | grep -v "^#"
echo ""

# 3. 训练模型
echo "3. 使用配置文件训练模型..."
cat test_data_fm.txt | ./bin/ffm_train \
    -m model_with_config.txt \
    -field_config field_config_test.txt \
    -dim 1,1,8 \
    -w_alpha 0.05 -w_beta 1.0 -w_l1 0.1 -w_l2 5.0 \
    -v_alpha 0.05 -v_beta 1.0 -v_l1 0.1 -v_l2 5.0 \
    -core 1 2>&1 | grep -E "Loaded|field|output"
echo ""

# 4. 查看模型中的域
echo "4. 模型中的域定义:"
head -1 model_with_config.txt
echo ""

# 5. 预测
echo "5. 使用配置文件进行预测..."
cat test_data_fm.txt | ./bin/ffm_predict \
    -m model_with_config.txt \
    -field_config field_config_test.txt \
    -dim 8 \
    -out predictions_with_config.txt \
    -core 1 2>&1 | grep -E "Loaded|field|loading"
echo ""

# 6. 查看预测结果
echo "6. 预测结果 (前5行):"
head -5 predictions_with_config.txt
echo ""

echo "=========================================="
echo "示例完成！"
echo ""
echo "配置文件模式的优势："
echo "  1. 样本文件简洁 (FM格式)"
echo "  2. 灵活控制特征到域的映射"
echo "  3. 减少参数量，提高训练效率"
echo "=========================================="

