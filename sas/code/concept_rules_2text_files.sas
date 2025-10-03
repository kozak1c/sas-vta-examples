
/******************************************************************************\
 * $Id: $
 *
 * Copyright(c) 2025 Corey Kozak (cokoza)
 *
 * Name          : concept_rules_2text_files.sas
 *
 * Purpose       : Export the contents of one or more VTA projects from a SAS dataset 
 *                 to a structured directory hierarchy. For each project, pipelines,
 *                 nodes, and concepts are materialized as nested folders.
 *                 Each concept is exported to two files:
 *                     - <concept_name>.txt  : Ordered concept rule lines (one per line)
 *                     - <concept_name>.info : Metadata (taxonomy_id, authorship, 
 *                                              dates, case sensitivity, priority)
 *                 
 *                 The export process ensures reproducibility by clearing and 
 *                 recreating a dedicated "_concept_definition_rules" subfolder under
 *                 each project directory before writing new files.
 *
 * Author        : Corey Kozak (cokoza)
 *
 * Support       : SAS Applied AI & Modeling (AAIM)
 *
 * Input(s)      : SAS libname and dataset containing VTA project concepts
 *
 * Output(s)     : Nested folders for each project/pipeline/node/concept, containing:
 *                   - <concept_name>.txt
 *                   - <concept_name>.info
 *
 * Parameters    : vta_project_saslib - SAS library containing the project dataset
 *               : vta_project_dsin   - Dataset name of the project concepts
 *               : vta_project_outdir - Root directory for exporting project hierarchy
 *
 * Dependencies  : Prior execution of the concept export script to create the SAS dataset
                   which is used as input to this program
 *
 * Assumptions   : 
 *                 - Dataset contains columns: project_name, pipeline_name, node_name,
 *                   concept_name, rule_line, rule_line_id, taxonomy_id, created_by,
 *                   modified_by, create_dt, modified_dt, caseinsensitive, priority, enabled
 *                 - Parent-child concept relationships are encoded in fullpath field
 *                 - Write-access to the output directory
 *
 * Usage         : Run the program in a SAS session supporting PROC PYTHON
 *
 * History
 *
 *   Date     	User    Brief Comment
 *   ---------	------  --------------------------------------
 *   18AUG2025	cokoza	Initial creation
 *   21AUG2025  lwright modified for Modeling Prod
\******************************************************************************/

/***** USER EDIT SECTION *****/
%let user_id=lwright;
/* name of git repository directory */
%let git_dir=git_4_models;
/* SAS library where the VTA export dataset is stored*/
%let vta_project_saslib=casuser;
/* Name of the VTA dataset containing projects, concepts, rules, and metadata */
%let vta_project_dsin=concepts_expand;
/* Root directory where project exports will be written */
*%let vta_project_outdir=/aaim_shared_data/SDV/code/cokoza/vta_blog/output;
%let vta_project_outdir=/shared/workspace/&user_id./&git_dir./VTAConceptDefinitions;

/***** END USER EDIT SECTION *****/

proc python;
submit;
import os
import shutil
import pandas as pd

# -----------------------------
# Macro variable inputs
# -----------------------------
saslib = SAS.symget("vta_project_saslib").strip('"').strip("'")
dsin   = SAS.symget("vta_project_dsin").strip('"').strip("'")
outdir = SAS.symget("vta_project_outdir").strip('"').strip("'")

# -----------------------------
# Load dataset and normalize
# -----------------------------
df = SAS.sd2df(f"{saslib}.{dsin}")
df.columns = df.columns.str.lower()  # lowercase columns
df = df.sort_values("rule_line_id")  # ensure rules are ordered

# -----------------------------
# Structure check
# -----------------------------
expected_cols = [
    "project_name","pipeline_name","node_name","concept_name","fullpath",
    "caseinsensitive","priority","taxonomy_id","created_by","modified_by",
    "create_dt","modified_dt","rule_line","rule_line_id"
]
missing = set(expected_cols) - set(df.columns)
if missing:
    raise ValueError(f"Missing expected columns: {missing}")

# -----------------------------
# Iterate over projects
# -----------------------------
for project_name, proj_df in df.groupby("project_name"):
    project_dir = os.path.join(outdir, project_name)
    export_root = os.path.join(project_dir, "_concept_definition_rules")

    # Clear only the _concept_definition_rules folder if it exists
    if os.path.exists(export_root):
        shutil.rmtree(export_root)
    os.makedirs(export_root, exist_ok=True)

    # -----------------------------
    # Iterate over pipelines
    # -----------------------------
    for pipeline_name, pipe_df in proj_df.groupby("pipeline_name"):
        pipeline_dir = os.path.join(export_root, pipeline_name)
        os.makedirs(pipeline_dir, exist_ok=True)

        # -----------------------------
        # Iterate over nodes
        # -----------------------------
        for node_name, node_df in pipe_df.groupby("node_name"):
            node_dir = os.path.join(pipeline_dir, node_name)
            os.makedirs(node_dir, exist_ok=True)

            # -----------------------------
            # Iterate over concepts
            # -----------------------------
            for concept_name, concept_df in node_df.groupby("concept_name"):
                # Use fullpath to create parent/child hierarchy
                fullpath = concept_df.iloc[0]["fullpath"]

                # Strip everything before first colon
                if ":" in fullpath:
                    fullpath = fullpath.split(":", 1)[1]

                concept_dir = os.path.join(node_dir, *fullpath.split("/"))
                os.makedirs(concept_dir, exist_ok=True)

                # Only terminal folder gets the rule files
                txtfile = os.path.join(concept_dir, f"{concept_name}.txt")
                infofile = os.path.join(concept_dir, f"{concept_name}.info")

                # Write rule lines as a single txt file
                lines = concept_df.sort_values("rule_line_id")["rule_line"].tolist()
                with open(txtfile, "w", encoding="utf-8") as f:
                    f.write("\n".join(lines))

                # Write metadata
                row = concept_df.iloc[0]
                case_insensitive = int(row["caseinsensitive"]) if not pd.isna(row["caseinsensitive"]) else None
                priority = int(row["priority"]) if not pd.isna(row["priority"]) else None
                enabled = int(row["enabled"]) if not pd.isna(row["enabled"]) else None

                metadata = {
                    "project_name": project_name,
                    "concept_name": row["concept_name"],
                    "taxonomy_id": row["taxonomy_id"],
                    "created_by": row["created_by"],
                    "modified_by": row["modified_by"],
                    "create_dt": row["create_dt"],
                    "modified_dt": row["modified_dt"],
                    "case_insensitive": case_insensitive,
                    "priority": priority,
                    "enabled": enabled,
                }

                with open(infofile, "w", encoding="utf-8") as f:
                    for k, v in metadata.items():
                        f.write(f"{k}: {v}\n")

                print(f"Wrote: {txtfile}, {infofile}")
endsubmit;
run;