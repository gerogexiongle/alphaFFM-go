#!/bin/bash
# FFM训练和预测演示脚本

echo "=========================================="
echo "alphaFFM-go 演示"
echo "=========================================="
echo ""

# 检查测试数据
if [ ! -f "test_data.txt" ]; then
    echo "错误: test_data.txt 文件不存在"
    exit 1
fi

echo "1. 训练 FFM 模型..."
echo "   命令: cat test_data.txt | ./bin/ffm_train -m demo_model.txt -dim 1,1,4 -core 1"
echo ""
cat test_data.txt | ./bin/ffm_train -m demo_model.txt -dim 1,1,4 -core 1

echo ""
echo "2. 查看模型文件前几行..."
head -5 demo_model.txt
echo ""

echo "3. 使用模型进行预测..."
echo "   命令: cat test_data.txt | ./bin/ffm_predict -m demo_model.txt -dim 4 -out demo_predictions.txt -core 1"
echo ""
cat test_data.txt | ./bin/ffm_predict -m demo_model.txt -dim 4 -out demo_predictions.txt -core 1

echo ""
echo "4. 查看预测结果..."
cat demo_predictions.txt
echo ""

echo "=========================================="
echo "演示完成！"
echo "=========================================="
echo ""
echo "生成的文件:"
echo "  - demo_model.txt: FFM模型文件"
echo "  - demo_predictions.txt: 预测结果"
echo ""

