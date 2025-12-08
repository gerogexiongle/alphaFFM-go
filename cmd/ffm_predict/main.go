package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/xiongle/alphaFFM-go/pkg/frame"
	"github.com/xiongle/alphaFFM-go/pkg/model"
	"github.com/xiongle/alphaFFM-go/pkg/simd"
)

func predictHelp() string {
	return `
usage: cat sample | ./ffm_predict [<options>]

options:
-m <model_path>: set the model path
-mf <model_format>: set the model format, txt or bin	default:txt
-dim <factor_num>: dim of 2-way interactions	default:8
-core <threads_num>: set the number of threads	default:1
-out <predict_path>: set the predict path
-mnt <model_number_type>: double or float	default:double
-simd <simd_type>: SIMD optimization type (scalar, blas)	default:scalar
-field_config <config_path>: field mapping config file (JSON or text format)
`
}

func main() {
	// 定义命令行参数
	opt := model.NewPredictorOption()

	modelPath := flag.String("m", "", "model path")
	modelFormat := flag.String("mf", "txt", "model format")
	dim := flag.Int("dim", 8, "factor num")
	core := flag.Int("core", 1, "threads num")
	out := flag.String("out", "", "predict path")
	mnt := flag.String("mnt", "double", "model number type")
	simdType := flag.String("simd", "scalar", "SIMD optimization type")
	fieldConfig := flag.String("field_config", "", "field mapping config file")

	flag.Parse()

	// 设置选项
	opt.ModelPath = *modelPath
	opt.ModelFormat = *modelFormat
	opt.FactorNum = *dim
	opt.ThreadsNum = *core
	opt.PredictPath = *out
	opt.ModelNumberType = *mnt
	opt.FieldConfigPath = *fieldConfig
	
	// 解析SIMD类型
	parsedSIMD, err := simd.ParseVectorOpsType(*simdType)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid simd type: %v\n", err)
		fmt.Fprint(os.Stderr, predictHelp())
		os.Exit(1)
	}
	opt.SIMDType = parsedSIMD

	// 验证参数
	if opt.ModelPath == "" {
		fmt.Fprintln(os.Stderr, "model path required")
		fmt.Fprint(os.Stderr, predictHelp())
		os.Exit(1)
	}

	if opt.PredictPath == "" {
		fmt.Fprintln(os.Stderr, "predict path required")
		fmt.Fprint(os.Stderr, predictHelp())
		os.Exit(1)
	}

	// 创建预测器
	predictor, err := model.NewFFMPredictor(opt)
	if err != nil {
		fmt.Fprintf(os.Stderr, "create predictor error: %v\n", err)
		os.Exit(1)
	}
	defer predictor.Close()

	// 运行预测框架
	pcFrame := frame.NewPCFrame()
	pcFrame.Init(predictor, opt.ThreadsNum)
	if err := pcFrame.Run(os.Stdin); err != nil {
		fmt.Fprintf(os.Stderr, "prediction error: %v\n", err)
		os.Exit(1)
	}
}

