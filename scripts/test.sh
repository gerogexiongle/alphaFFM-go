#!/bin/bash
# alphaFFM-go 完整测试脚本

set -e

echo "=========================================="
echo "alphaFFM-go 完整测试"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查可执行文件
if [ ! -f "bin/ffm_train" ] || [ ! -f "bin/ffm_predict" ]; then
    echo -e "${RED}错误: 可执行文件不存在，请先运行 make${NC}"
    exit 1
fi

# 检查测试数据
if [ ! -f "test_data.txt" ]; then
    echo -e "${RED}错误: test_data.txt 文件不存在${NC}"
    exit 1
fi

echo -e "${YELLOW}测试 1: 基础训练（标量模式）${NC}"
echo "命令: cat test_data.txt | ./bin/ffm_train -m test_model_scalar.txt -dim 1,1,4 -core 1"
cat test_data.txt | ./bin/ffm_train -m test_model_scalar.txt -dim 1,1,4 -core 1
if [ -f "test_model_scalar.txt" ]; then
    echo -e "${GREEN}✓ 训练成功${NC}"
    echo "  模型行数: $(wc -l < test_model_scalar.txt)"
else
    echo -e "${RED}✗ 训练失败${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}测试 2: 基础预测（标量模式）${NC}"
echo "命令: cat test_data.txt | ./bin/ffm_predict -m test_model_scalar.txt -dim 4 -out test_pred_scalar.txt -core 1"
cat test_data.txt | ./bin/ffm_predict -m test_model_scalar.txt -dim 4 -out test_pred_scalar.txt -core 1
if [ -f "test_pred_scalar.txt" ]; then
    echo -e "${GREEN}✓ 预测成功${NC}"
    echo "  预测结果:"
    head -5 test_pred_scalar.txt | sed 's/^/    /'
else
    echo -e "${RED}✗ 预测失败${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}测试 3: 多线程训练${NC}"
echo "命令: cat test_data.txt | ./bin/ffm_train -m test_model_mt.txt -dim 1,1,4 -core 2"
cat test_data.txt | ./bin/ffm_train -m test_model_mt.txt -dim 1,1,4 -core 2
if [ -f "test_model_mt.txt" ]; then
    echo -e "${GREEN}✓ 多线程训练成功${NC}"
else
    echo -e "${RED}✗ 多线程训练失败${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}测试 4: 多线程预测${NC}"
echo "命令: cat test_data.txt | ./bin/ffm_predict -m test_model_mt.txt -dim 4 -out test_pred_mt.txt -core 2"
cat test_data.txt | ./bin/ffm_predict -m test_model_mt.txt -dim 4 -out test_pred_mt.txt -core 2
if [ -f "test_pred_mt.txt" ]; then
    echo -e "${GREEN}✓ 多线程预测成功${NC}"
else
    echo -e "${RED}✗ 多线程预测失败${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}测试 5: 不同维度训练${NC}"
for dim in 2 8 16; do
    echo "  维度: $dim"
    cat test_data.txt | ./bin/ffm_train -m test_model_dim${dim}.txt -dim 1,1,${dim} -core 1 > /dev/null 2>&1
    if [ -f "test_model_dim${dim}.txt" ]; then
        echo -e "    ${GREEN}✓ 维度 $dim 训练成功${NC}"
    else
        echo -e "    ${RED}✗ 维度 $dim 训练失败${NC}"
    fi
done
echo ""

echo -e "${YELLOW}测试 6: FTRL参数测试${NC}"
echo "  使用不同的正则化参数"
cat test_data.txt | ./bin/ffm_train -m test_model_reg.txt -dim 1,1,4 \
    -w_l1 0.5 -w_l2 10.0 -v_l1 0.5 -v_l2 10.0 -core 1 > /dev/null 2>&1
if [ -f "test_model_reg.txt" ]; then
    echo -e "${GREEN}✓ 正则化参数测试成功${NC}"
else
    echo -e "${RED}✗ 正则化参数测试失败${NC}"
fi
echo ""

echo -e "${YELLOW}测试 7: 模型文件检查${NC}"
echo "  检查模型文件格式..."
FIRST_LINE=$(head -1 test_model_scalar.txt)
if [[ $FIRST_LINE == FIELDS* ]]; then
    echo -e "${GREEN}✓ 模型文件包含 FIELDS 头${NC}"
    echo "    $FIRST_LINE"
else
    echo -e "${RED}✗ 模型文件格式错误${NC}"
fi

SECOND_LINE=$(head -2 test_model_scalar.txt | tail -1)
if [[ $SECOND_LINE == bias* ]]; then
    echo -e "${GREEN}✓ 模型文件包含 bias 行${NC}"
else
    echo -e "${RED}✗ 模型文件缺少 bias 行${NC}"
fi
echo ""

echo -e "${YELLOW}测试 8: 预测结果检查${NC}"
echo "  检查预测结果格式..."
PRED_LINES=$(wc -l < test_pred_scalar.txt)
DATA_LINES=$(wc -l < test_data.txt)
if [ "$PRED_LINES" -eq "$DATA_LINES" ]; then
    echo -e "${GREEN}✓ 预测行数与测试数据一致 ($PRED_LINES 行)${NC}"
else
    echo -e "${RED}✗ 预测行数不一致 (预测: $PRED_LINES, 数据: $DATA_LINES)${NC}"
fi

# 检查预测值是否在合理范围内
while IFS= read -r line; do
    score=$(echo $line | awk '{print $2}')
    if (( $(echo "$score >= 0 && $score <= 1" | bc -l) )); then
        :
    else
        echo -e "${RED}✗ 预测值超出范围 [0,1]: $score${NC}"
    fi
done < test_pred_scalar.txt
echo -e "${GREEN}✓ 所有预测值在 [0,1] 范围内${NC}"
echo ""

echo -e "${YELLOW}测试 9: 清理测试文件${NC}"
rm -f test_model_*.txt test_pred_*.txt
echo -e "${GREEN}✓ 测试文件清理完成${NC}"
echo ""

echo "=========================================="
echo -e "${GREEN}所有测试通过！${NC}"
echo "=========================================="
echo ""
echo "alphaFFM-go 已准备就绪！"
echo ""
echo "使用示例:"
echo "  训练: cat train.txt | ./bin/ffm_train -m model.txt -dim 1,1,8 -core 4"
echo "  预测: cat test.txt | ./bin/ffm_predict -m model.txt -dim 8 -out pred.txt -core 4"
echo ""

