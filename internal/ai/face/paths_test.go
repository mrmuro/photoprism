package face

import (
	"path/filepath"
)

var assetsModelsPath, _ = filepath.Abs("../../../assets/models")
var modelPath = filepath.Join(assetsModelsPath, "facenet")

// detectorModelPath names the detector a build ships rather than a fixed directory, so the
// detector-dependent tests keep running against whatever "make dep-models" installs.
var detectorModelPath = DefaultDetector().Path(assetsModelsPath)
