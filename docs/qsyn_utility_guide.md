## QSYN utility

## Objective

Ensure the correctness and quality of our logic design code by evaluating:

- 1. Synthesizability Confirming that the design can be translated into logic for implementation.

- 2. Feasibility Ensuring the synthesized design meets predefined constraints on gate count and clock frequency, as specified for each assignment.

Keep in mind that a successful simulation does not ensure synthesizability, as it may mask issues like race

conditions and combinatorial loops. Conversely, non-synthesizable code can lead to incorrect and unpredictable behavior during simulation. Therefore, it is advisable to verify synthesizability before running simulations.

## Method

To verify synthesizability, we employ an FPGA synthesis flow using the Intel-Altera Quartus tool. Although

FPGAs and ASICs have significant differences, the guidelines for writing synthesizable code remain similar. In many cases, the same RTL source code can be used for both FPGA and ASIC implementations. Regarding feasibility, while FPGAs offer post-manufacturing programmability, they typically exhibit an order of magnitude worse performance in terms of area and speed compared to ASICs within the same manufacturing node.

## Initial Setup

In your BIU-Engineering cloud environment open a terminal anywhere and enter the following command:

```
source /project/tsmc65/shared/qsyn/util/qsyn_install.sh
```

This only needs to be executed once ever, and should take just a few seconds. It will permanently configure

your account access to the utility. Once the setup is complete, close the terminal and open a new one to continue with the next steps.

## Usage Example

The most effective way to become familiar with the utility is by using a provided reference example.

To do so, open a new terminal and perform following steps:

```
tsmc65 ;# Enter tsmc65 environment
cd $ws ;# Go to your workspace
mkdir -p tmp ;# Create a temporary folder
cd tmp ;# Go into the temporary folder
cp -r $QSYN/syn_check_example ./ ;# Copy the reference example to your space.
cd syn_check_example ;# Go into the example folder
```


The current folder ... tmp/syn_check_example now contains our design.

This design outputs the data from the port with the highest value among four input ports. consisting of two

hierarchical simple System-Verilog modules that you can review.

- 1. max2.sv A sub-module that outputs the sampled maximum value between two input ports.

- 2. max4.sv The top-level module utilizing max2.sv to select the maximum value among four input ports.

source_files_list.txt is a user provided text file require by the tool listing the project source files.

Each source file should be listed in a separate line with no comments in the file.

## Notice

- The list file should include only Verilog or System-Verilog files (*.sv or *.v) that make up the synthesized design.

- Do not include test-bench files, as they are not hardware-mappable and are not required to be synthesizable.

- Among the listed design files only one top-level module entity should appear (e.g., max4 in our example).

- If the design files are located outside the current folder, use relative paths (e.g., ../abc/xyz.sv).

- The clock signal if exists must be named clk, and the reset signal if exists must be named rst_n (which is also a common industry practice).

- The project name should match the top-level entity name (e.g., max4 in our example).

To execute the utility on the example design, enter the following commands. Each command may take a few

minutes, depending on the design's complexity. Since each command depends on the successful completion of the previous one, they must be run in the given order.

Check synthesizability report critical errors, and logic resources consumption.

qsyn max4 -syn

Check feasibility performers 'place and route' fitting into the device.

Check Timing Perform Static Timing Analysis (STA).

qsyn max4 -sta

Alternatively you can run all three above checks by:

qsyn max4 -all


Synthesizability Success Criteria Per each of the checks look for following response.

```
0 errors, 0 non-justified warnings
```

Otherwise, resolve the reported errors, which can be further analyzed using the indicated report file. Some

listed non-critical warnings may be initially waived , consult with course staff to waive.

Unless stated otherwise:

- The reported logic resources should be below 20,000 FPGA Logical Elements (equivalent to approximately 120,000 ASIC gates).

- The reported maximum frequency should be higher than 20 MHz on FPGA (equivalent to about 1 GHz on a 16nm ASIC).

## DDP26-Summer HW1 adjustment

We have all ready created the DDP26S HW1 QSYN source file list which also include some necessary glue

wrapper to the FPGA. Therefore to check your HW1 code synthesizability run the following from your workspace directory. (no need to create source_files_list.txt)

For the combinatorial version run:

```
qsyn is_legal_wrap -syn -sfl \$QSYN/ddp26s_hw1_ref/is_legal_comb_qsyn_list.txt
qsyn is_legal_wrap -fit -sfl $QSYN/ddp26s_hw1_ref/is_legal_comb_qsyn_list.txt
qsyn is_legal_wrap -sta -sfl $QSYN/ddp26s_hw1_ref/is_legal_comb_qsyn_list.txt
```

For the sequential version run:

```
qsyn is_legal_wrap -syn -sfl \$QSYN/ddp26s_hw1_ref/is_legal_seq_qsyn_list.txt
qsyn is_legal_wrap -fit -sfl $QSYN/ddp26s_hw1_ref/is_legal_seq_qsyn_list.txt
qsyn is_legal_wrap -sta -sfl $QSYN/ddp26s_hw1_ref/is_legal_seq_qsyn_list.txt
```

## Optional advanced Quartus GUI usage

This part is for general knowledge, not mandatory and better be skipped in the early stage of using the flow.

The Quartus utility offers a GUI interface for additional design analysis and visualization. Using the GUI is not

required for your assignments, but if you'd like to explore your design further, you can open the GUI and load your project as described below.

The QSYN flow mentioned above also generates a file named <ProjectName>.qpf (e.g., max4.qpf in the

example above). To open the Quartus GUI, use the following command in a terminal:

```
\$QBIN/quartus
```


Pull down File->Open ... and browse to and your project ".qpf file:

A basic tutorial of the GUI usage is available here:

[Intel Quartus Software – GUI Introduction - Part 1 of 6](https://www.youtube.com/watch?v=iYcZCx5XmtA)

## GOOD LUCK
