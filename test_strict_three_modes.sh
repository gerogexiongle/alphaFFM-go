#!/bin/bash
# 测试三种严格模式（去掉Auto模式后）

echo "=========================================="
echo "测试三种严格模式"
echo "=========================================="
echo ""

# 模式1: 显式域名（FFM格式）- 不需要配置文件
echo "【模式1】显式域名 (FFM格式) - 成功"
echo "样本: 1 user:sex:1 user:age:0.3 item:f1:1"
echo "说明: 域名在样本中显式指定"
echo ""
echo "1 user:sex:1 user:age:0.3 item:f1:1" | ./bin/ffm_train \
    -m model_explicit.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "output|Warning|Error|failed"
if [ -f model_explicit.txt ]; then
    echo "✅ 模式1成功"
    head -1 model_explicit.txt
else
    echo "❌ 模式1失败"
fi
echo ""
echo "---"
echo ""

# 模式2: FM格式但没有配置文件 - 应该报错
echo "【模式2】FM格式但没有配置文件 - 报错"
echo "样本: 1 sex:1 age:0.3 f1:1"
echo "说明: FM格式必须提供配置文件"
echo ""
echo "1 sex:1 age:0.3 f1:1" | ./bin/ffm_train \
    -m model_no_config.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "Warning|Error|failed|requires"
if [ ! -f model_no_config.txt ]; then
    echo "✅ 模式2正确报错，没有生成模型"
else
    echo "❌ 模式2失败，不应该生成模型"
fi
echo ""
echo "---"
echo ""

# 模式3: 小特征 + 配置文件 - 成功
echo "【模式3】小特征 + 配置文件 - 成功"
echo "样本: 1 sex:1 age:0.3 f1:1"
echo "配置: sex→user, age→user, f1→item"
echo ""
echo "1 sex:1 age:0.3 f1:1" | ./bin/ffm_train \
    -m model_with_config.txt \
    -field_config field_config_numeric.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "Loaded|output|Warning|Error"
if [ -f model_with_config.txt ]; then
    echo "✅ 模式3成功"
    head -1 model_with_config.txt
else
    echo "❌ 模式3失败"
fi
echo ""
echo "---"
echo ""

# 模式4: 小特征未配置 - 报错
echo "【模式4】小特征未配置 - 报错"
echo "样本: 1 unknown:1 sex:1"
echo "说明: unknown不在配置中"
echo ""
echo "1 unknown:1 sex:1" | ./bin/ffm_train \
    -m model_unknown.txt \
    -field_config field_config_numeric.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "Warning|not found|failed"
if [ ! -f model_unknown.txt ]; then
    echo "✅ 模式4正确报错，没有生成模型"
else
    echo "❌ 模式4失败"
fi
echo ""
echo "---"
echo ""

# 模式5: 大数字特征 - 自动提取，不需配置
echo "【模式5】大数字特征 - 自动提取"
echo "样本: 1 51539607553:1 55834574849:1 sex:1"
echo "说明: 大数字自动提取高32位，小特征需要配置"
echo ""
echo "1 51539607553:1 55834574849:1 sex:1" | ./bin/ffm_train \
    -m model_numeric.txt \
    -field_config field_config_numeric.txt \
    -dim 1,1,4 \
    -core 1 2>&1 | grep -E "Loaded|output|Warning|Error"
if [ -f model_numeric.txt ]; then
    echo "✅ 模式5成功"
    head -1 model_numeric.txt
else
    echo "❌ 模式5失败"
fi
echo ""

echo "=========================================="
echo "总结: 三种严格模式"
echo ""
echo "1. 显式域名 (FFM格式):"
echo "   格式: label field:feature:value"
echo "   要求: 不需要配置文件"
echo ""
echo "2. 小特征 + 配置文件:"
echo "   格式: label feature:value"
echo "   要求: 必须提供配置文件，特征必须在配置中"
echo ""
echo "3. 大数字特征 (>= 1000000):"
echo "   格式: label feature:value"
echo "   要求: 自动提取高32位，不需要配置"
echo ""
echo "注意: FM格式(label feature:value)必须提供配置文件"
echo "      否则报错!"
echo "=========================================="

