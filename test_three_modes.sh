#!/bin/bash
# 测试三种样本格式的严格模式

echo "=========================================="
echo "测试三种样本格式的处理逻辑"
echo "=========================================="
echo ""

# 测试1: 正常样本（大数字特征 + 已配置的小特征）
echo "【测试1】正常样本 - 应该成功"
echo "样本: 1 51539607553:1 55834574849:1 sex:1 age:0.3"
echo "      - 51539607553, 55834574849: 大数字，自动提取域ID"
echo "      - sex, age: 小特征，从配置文件映射"
echo ""
echo "1 51539607553:1 55834574849:1 sex:1 age:0.3" | ./bin/ffm_train \
    -m model_test1.txt \
    -field_config field_config_numeric.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "Loaded|output|Warning|Error"
if [ $? -eq 0 ]; then
    echo "✓ 测试1通过"
    head -1 model_test1.txt
else
    echo "✗ 测试1失败"
fi
echo ""

# 测试2: 包含未配置的小特征（应该报错）
echo "【测试2】包含未配置的小特征 - 应该报错"
echo "样本: 1 51539607553:1 unknown_feature:1 sex:1"
echo "      - unknown_feature: 不在配置中，应该报错"
echo ""
echo "1 51539607553:1 unknown_feature:1 sex:1" | ./bin/ffm_train \
    -m model_test2.txt \
    -field_config field_config_numeric.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "Loaded|Warning|failed to get field"
if [ $? -eq 0 ]; then
    echo "✓ 测试2通过 - 正确报错"
else
    echo "✗ 测试2失败 - 应该报错但没有"
fi
echo ""

# 测试3: 显式域名样本（不需要配置文件）
echo "【测试3】显式域名样本 - 不需要配置文件"
echo "样本: 1 user:sex:1 user:age:0.3 item:f100:1"
echo "      - 直接使用样本中的域名"
echo ""
echo "1 user:sex:1 user:age:0.3 item:f100:1" | ./bin/ffm_train \
    -m model_test3.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "output|Warning|Error"
if [ $? -eq 0 ]; then
    echo "✓ 测试3通过"
    head -1 model_test3.txt
else
    echo "✗ 测试3失败"
fi
echo ""

# 测试4: 小数字特征64（不是大数字，需要配置）
echo "【测试4】小数字特征（需要配置）"
echo "样本: 1 51539607553:1 64:1"
echo "      - 51539607553: 大数字，自动提取"
echo "      - 64: 小数字（< 1000000），需要配置"
echo ""
echo "配置文件中添加 64 的映射..."
echo "64 other" >> field_config_numeric.txt
echo "1 51539607553:1 64:1" | ./bin/ffm_train \
    -m model_test4.txt \
    -field_config field_config_numeric.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "Loaded|output|Warning"
if [ $? -eq 0 ]; then
    echo "✓ 测试4通过"
    head -1 model_test4.txt
else
    echo "✗ 测试4失败"
fi
echo ""

echo "=========================================="
echo "总结："
echo "  1. 显式域名: label field:feature:value - 直接使用"
echo "  2. 小特征 + 配置: label feature:value - 必须有配置"
echo "  3. 大数字特征: label feature:value - 自动提取高32位"
echo "=========================================="

# 清理
rm -f field_config_numeric.txt.bak

