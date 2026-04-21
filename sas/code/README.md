# README

This README file associates the seven SAS programs residing in this git repository, with the respective articles in the series *Tips and Tricks for Power Users of SAS® Visual Text Analytics.* All four articles are listed and linked below. Each SAS program may be used in SAS Studio, without reference to this git repository, for the purposes stated below.

Note: This series of articles focuses solely on information extraction models built with SAS Visual Text Analytics (VTA) in SAS Model Studio with each VTA project containing one Data node and one Concept node. Use of these programs with additional pipeline nodes has not been tested.

### [Part 1 of 3 (Structuring Concepts)](https://communities.sas.com/t5/SAS-Communities-Library/Tips-and-Tricks-for-Power-Users-of-SAS-Visual-Text-Analytics/ta-p/976077)

&nbsp;&nbsp;&nbsp;&nbsp;This article provides organizational structure for creating custom concepts in the Concept node of a VTA project in SAS Model Studio. These tips and tricks have proved invaluable for maintaining multiple VTA projects over many years of development. No programs in this git repository are associated with this article.

### [Part 2 of 3 (API Hacks)](https://communities.sas.com/t5/SAS-Communities-Library/Tips-and-Tricks-for-Power-Users-of-SAS-Visual-Text-Analytics/ta-p/976072)

The following three SAS programs provide programmatic manipulation of custom concepts in a VTA project, independent of the SAS Model Studio user interface, once the project is exported. One significant benefit of this process is version tracking for all VTA projects at the custom concept level.

1. *export_concept_rules.sas* – this program programmatically exports the custom concepts in a Concept node, from a VTA project residing in SAS Model Studio, to a SAS dataset.
2. *Concept_rules_2text_files.sas* – uses the output dataset, from the SAS program in #1 above, to build a structured directory of text files on the server. Each text file contains the content of each custom concept; each line in a custom concept is either a comment or a concept definition rule (CDR). The name of the text file is populated with the name of the custom concept. Association of this program with a git repository allows version tracking with a new version available for each execution of the program.
3. *import_concept_rules.sas* – uses the output dataset from the SAS program in #1, which can be modified as the user desires, as input to an empty Concept node in a VTA project. This SAS program allows facile creation of a new <u>customized</u> VTA project that is any logical combination of two or more existing VTA projects, each previously exported with program #1.

### [Part 3 of 3 (Tracking Concept Rules)](https://communities.sas.com/t5/SAS-Communities-Library/Tips-and-Tricks-for-Power-Users-of-SAS-Visual-Text-Analytics/ta-p/975817)

&nbsp;&nbsp;&nbsp;&nbsp;The following programs allow facile quality assurance during the development cycle. Each program requires prior execution of two programs described in Part 2 of 3 (API Hacks) shown above, programs #1 and #2.

4. *Concept_Reference_Check.sas* – checks that any custom concept is appropriately referenced by another concept. Output from the program lists any concept <u>not</u> referenced. Identifies any stale concepts – concepts not referenced.
5. *CDR_Text_Check.sas* – used to confirm the presence or absence of specified text within any rule/CDR in the custom concepts of a VTA project. This program is useful for finding specific CDR types, like a REMOVE_ITEM rule, finding any text string within a CDR, or finding a custom concept name within a CDR. All comment lines are ignored.
6. *Concept_Header_Check.sas* – a modification of the program listed in #5 above, to assess only the comment lines, representing the header for a custom concept, in all custom concepts of a VTA project. Output from this program lists any missing elements/text string that we require in the header.

### [Problematic CDRs](https://communities.sas.com/t5/tkb/workflowpage/tkb-id/library/article-id/11561)

7. *Find_matching_CDRs_in_Custom_Concept.sas* – used to troubleshoot false positive and/or false negative results for an existing VTA project in SAS Model Studio. The user needs to provide the project name, the custom concept name, the observation producing the undesired match, and the matched text string. The entire observation is required due to the contextual nature of information extraction models. To access the observation, the program requires the unique id of the observation, the name of the table containing the observation, and the name of the caslib where the table resides. Note: the table must comply with listed requirements and be loaded into memory.
