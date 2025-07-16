# How to use the QNN wrapper scripts

These scripts are here to leverage the Qualcomm QNN SDK in order to allow easy conversion, compilation, quantization and inference running of models on device.

## 1. Setup

First of all, all these scripts respect a common project structure.
Create the following arborescence of folders where you want to have your work environment:

```
.
└── Qualcomm
    ├── environment
    │   ├── sdks
    │   └── virtual_environments
    ├── projects
    └── scripts
```

Then, move the scripts and config files that are in this repository inside the "scripts" folder. In this folder, execute `chmod +x *.sh` to grant them execution permission.

The next step is to install the various SDKs and tools, that are not included in this repository and that you need to install yourself.

- **Cross-compilation toolchain**: https://thundercomm.s3.ap-northeast-1.amazonaws.com/uploads/web/rubik-pi-3/20250325/toolchains_V1.1.0.zip
- **QNN SDK**: https://www.qualcomm.com/developer/software/qualcomm-ai-engine-direct-sdk
- **(optional) QIRP SDK**: https://www.qualcomm.com/developer/software/qualcomm-intelligent-robotics-product-sdk

Then, extract the files and install everything. To setup toolchains, run:

```bash
cd toolchains
chmod 755 qcom-wayland-x86_64-qcom-multimedia-image-armv8-2a-qcm6490-idp-toolchain-ext-1.3-ver.1.1.sh
sh qcom-wayland-x86_64-qcom-multimedia-image-armv8-2a-qcm6490-idp-toolchain-ext-1.3-ver.1.1.sh
```

Then, move the folders so that they respect the following structure:

```
.
└── Qualcomm
    ├── environment
    │   ├── sdks
    │   │   ├── qcom_wayland_sdk
    │   │   ├── qirp
    │   │   │   └── qcm6490
    │   │   ├── qnn
    │   │   │   └── qairt
    │   │   │       └── 2.35.x.xxxxxx
    │   │   └── toolchains
    │   └── virtual_environments
    ├── projects
    └── scripts
```

Finally, create a python 3.10 virtual environment named "qai_hub" under the "virtual_environments" folder.

The final step is to open `config.json` and put in your Qualcomm AI Hub API token.
You will also see that there are some configurable options (the active project one will be set later), for now they do not need to be touched. Setup should be done.

## 2. Project creation

Now, you can use the various scripts inside a project.

The first step is to finalize your environment and activate it with:

```bash
source environment_setup.sh
```

(be careful to use `source` so that environment variables stay persistent. This is the only script which requires `source`)

Then, once that is fully validated, projects are managed using the `manage_project.sh` script. Simply run:

```bash
./manage_project.sh -h
```

And let the description guide you. Create your first project, and set it as active. You can now start using the other scripts.

## 3. Script utilization

To know how to use a script, simply call it with `-h` and all the documentation will be displayed. I will now describe the order in which to use them:

1. **environment_setup.sh**: set up the environment, run it whenever you use a new terminal
2. **create_list.sh**: optional, create input list for quantization (if you want to use quantization)
3. **convert.sh**: converts a model (ONNX for example) into the QNN format: `.cpp`/`.bin`. Allows quantization when specified
4. **compile.sh**: compiles a QNN format converted model into a `.so` shared library format for execution
5. **create_list.sh**: this time, non optional: create the input list to run the inference
6. **qnn_inference.sh**: run the inference on target
7. **qnn_pull.sh**: pull the results from inference runs
8. **batch_inference.sh**: optional, uses `qnn_inference.sh`, `qnn_pull.sh`, and `extract_metrics.sh` in order to run inferences in batch based on the `model_list.json`

### Special mentions:

- **model_list_test.json**: an example of the structure of the model list
- **profile_config.json**: inference performance profiles
- **qnn_log_parser.py**: attempt at parsing the log files of the inferences, but isn't working for now (all values are the same when analyzing various models) -> needs to be fixed

## 4. Folder structure

The structure of a project will look like:

```
.
└── project
    ├── data
    ├── models
    └── outputs
```

All the scripts will take paths for their arguments that are relative to the active project root folder, and its subfolders. These relative paths are specified in the description whenever you call the script with `-h`, should you need to check.

The use of an active project inside the `config.json` file and shared environment variables allows for readable commands that do not need absolute paths, and an overall smooth workflow once mastered.
