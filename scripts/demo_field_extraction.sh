#!/bin/bash
# Field 提取机制演示

echo "=========================================="
echo "FFM Field 自动提取机制演示"
echo "=========================================="
echo ""

cd /data/xiongle/alphaFFM-go

echo "1. 使用 FM 格式数据（自动提取 field）"
echo "----------------------------------------"
echo "数据格式: label feature:value feature:value ..."
echo ""
echo "示例数据 (test_data.txt):"
head -3 test_data.txt
echo ""

echo "训练模型..."
cat test_data.txt | ./bin/ffm_train -m model_auto.txt -dim 1,1,4 -core 1 2>&1 | grep -E "(output|finished)"
echo ""

echo "提取的 Field 列表:"
head -1 model_auto.txt
echo ""

echo "解释:"
echo "  - sex     → field = 'sex'  (整个特征名)"
echo "  - age     → field = 'age'  (整个特征名)"
echo "  - f1,f2,f3,f5,f8 → field = 'f'    (数字前的部分)"
echo ""
echo ""

echo "2. 使用 FFM 格式数据（显式指定 field）"
echo "----------------------------------------"
echo "数据格式: label field:feature:value field:feature:value ..."
echo ""
echo "示例数据 (test_data_explicit_field.txt):"
head -3 test_data_explicit_field.txt
echo ""

echo "训练模型..."
cat test_data_explicit_field.txt | ./bin/ffm_train -m model_explicit.txt -dim 1,1,4 -core 1 2>&1 | grep -E "(output|finished)"
echo ""

echo "提取的 Field 列表:"
head -1 model_explicit.txt
echo ""

echo "解释:"
echo "  每个 field 都被明确识别，FFM 可以精确建模不同 field 间的交互"
echo ""
echo ""

echo "=========================================="
echo "Field 数量对比"
echo "=========================================="
echo ""

AUTO_FIELDS=$(head -1 model_auto.txt | awk '{print NF-1}')
EXPLICIT_FIELDS=$(head -1 model_explicit.txt | awk '{print NF-1}')

echo "自动提取模式: $AUTO_FIELDS 个 field"
echo "显式指定模式: $EXPLICIT_FIELDS 个 field"
echo ""

AUTO_SIZE=$(wc -c < model_auto.txt)
EXPLICIT_SIZE=$(wc -c < model_explicit.txt)

echo "模型文件大小对比:"
echo "  自动提取: $AUTO_SIZE bytes"
echo "  显式指定: $EXPLICIT_SIZE bytes"
echo ""

echo "=========================================="
echo "Field 提取规则"
echo "=========================================="
echo ""
echo "代码位置: pkg/sample/sample.go"
echo ""
echo "规则1: 按下划线分割"
echo "  user_id_123  → field = 'user'"
echo "  price_high   → field = 'price'"
echo ""
echo "规则2: 按数字分割"
echo "  f1, f2, f3   → field = 'f'"
echo "  item100      → field = 'item'"
echo ""
echo "规则3: 默认使用整个特征名"
echo "  sex          → field = 'sex'"
echo "  age          → field = 'age'"
echo ""

echo "=========================================="
echo "最佳实践建议"
echo "=========================================="
echo ""
echo "✓ 测试阶段: 使用自动提取（兼容 FM 格式）"
echo "  - 优点: 方便快捷，可以直接用 FM 的数据"
echo "  - 缺点: field 可能不够精确"
echo ""
echo "✓ 生产环境: 使用显式 field 格式"
echo "  - 优点: FFM 效果更好，field 语义更明确"
echo "  - 缺点: 需要数据预处理"
echo ""

# 清理
rm -f model_auto.txt model_explicit.txt

echo "演示完成！详细说明请查看: docs/FIELD_EXTRACTION.md"
echo ""

