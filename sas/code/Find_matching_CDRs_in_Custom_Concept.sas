/******************************************************************************\
 * $Id: $lwright
 *
 * Copyright(c) 2026
 *
 * Name          : find_matching_CDRs_in_Custom_Concept.sas
 *
 * Purpose       : find the concept definition rule (CDR) or rules in a custom concept that matches specified text
 *
 * Author        : Bruce Mills, Corey Kozak, Lois Wright
 *
 * Input(s)      : VTA project name, custom concept name, text string that matches, source data caslib,
 *                  source data table name, unique row identifier for observation containing matched text string
 *
 * Output(s)     : SAS dataset in work library containing the CDR(s) that match the text string
 *
 * Dependencies  : valid inputs
 *
 * Usage         : Troubleshoot custom concept to find CDR(s) matching text string provided
 *
 * Expected      :  WARNING:  Apparent symbolic reference LIMIT not resolved.
 *                  WARNING:  Apparent symbolic reference FILTER not resolved.
 *                  WARNING:  File CASUSER.ERROR.DATA does not exist.
 * History
 *
 *   Date     	User    Brief Comment
 *   ---------	------  --------------------------------------
 *   18AUG2025	bmills	Initial creation of export_concept_rules_expanded.sas
 *   21AUG2025  lwright modified for Modeling Prod
 *   12JAN2026  lwright added code to find CDR in concept of interest that matches text string
 *   28JAN2026  lwright added error handling when no initial match
 *   03MAR2026  lwright added code to also find CDRs of PREDICATE_RULE and SEQUENCE from out_fact table
 *   05MAR2026  lwright remove MODEL ds writing to WORK
\******************************************************************************/
/******** CONTENTS ********/
/* 
Section 1 - user populated macro variables
Section 2 - export VTA project
Section 3 - subset source data to single obs and move to CASUSER
Section 4 - create initial model file, capture macvars, create shell
Section 5 - split custom concept and score with recursive macro, until terminal node reached (think decision tree)
Section 6 - output CDR(s) to table and print
Section 7 - clean up CASUSER, WORK and CASLIBS
*/
/* ******* NOTICE: ******* */
/* the value for the text_variable_name must not contain spaces */
/* the unique_row_id_name variable must be of data type character */
/* hence the unique_row_id_value will be of data type character */

/******** SECTION 1 ********/
/* USER ASSIGNED macro variables */

/* VTA Project Information */
%let sas_project_name = %upcase(color_project); *value is not case sensitive;

/* configure CAS session; must assign the caslib containing your VTA project source data */
%let cas_host = %str(sas-cas-server-xxxxxxxxxxxxx);
    options cashost="&cas_host" casport=5570 casdatalimit=ALL;
    cas;
    caslib _all_ assign;

/* Data Source Information */
%let datacaslib=%str(vtadata); *caslib for original VTA project source data;

/* use OPTIONAL CODE on lines 68-72 if you need to modify your original source data to comply with requirements, see NOTICE section above */
/* change unique_row_id_name data type from num to char and/or remove spaces in text_variable_name */
/* replace existing values, 'textvar with spaces'n and rowid_num, in code below with values from your source data */
/* otherwise insert name of original data set name on line 75 */
/* %let orig_tablename=%str(ds_color);  */
/* data &datacaslib..ds_color_final; */
/*     set &datacaslib..&orig_tablename(rename=('textvar with spaces'n=textvarnospaces)); *remove spaces in text variable name; */
/*     rowid_char=put(rowid_num,3.); *convert to data type char; *format must match values; */
/* run; */
/* end of OPTIONAL CODE */

%let datatablename=%str(ds_color); *version of data set, with observation containing matched_text, and meeting requirements;
%let text_variable_name = %str(pagetext); *see NOTICE section;
%let unique_row_id_name = %str(rowid); *see NOTICE section;

/* Search Criteria */
%let matched_text = %upcase(blue); *value is not case sensitive;
%let unique_row_id_value = %str(435-5-80); *see NOTICE section;
%let search_concept = %upcase(t_color); *value is not case sensitive;

/* END of USER edits */

/******** SECTION 2 ********/
/* EXPORT the contents of &sas_project_name to a SAS dataset */
/*************************/
options compress=yes;
%let BASE_URI=%sysfunc(getoption(servicesbaseurl));

/*Delete any previous Concept Export Tables*/
%if %sysfunc(exist(casuser.concept_export)) %then %do;
	proc delete data=casuser.concept_export;
	run;
%end;

/*Get a List of all the VTA model studio projects*/
filename projs temp;
proc http 
	url="&base_uri/analyticsGateway/projects?start=0&limit=9999&filter=in(projectType,%20%27text%27)"
	out=projs
	oauth_bearer=sas_services;
run;

libname projs json;

data _null_;
    put 'WARNING: The two warnings above for LIMIT and FILTER are expected.';
run;

/*Add filter for specific project of interest*/
data proj_filter;
	set projs.items;
    if upcase(name)="&sas_project_name." then output;
run;

/*Get the count of the VTA projects to Loop through  */
proc sql noprint;
	select count(*) into: proj_cnt
	from proj_filter;
quit;

/*Loop through all selected projects to extract rules  */
/* NOTE: known warning in log for LIMIT and FILTER */
/* COMPILE macro program */
%macro extract_loop;

%do proj_loop_id = 1 %to &proj_cnt;
	/*Defines macro variables for model studio UUID and Name for the project*/
	data _null_;
		set proj_filter;
		if _n_ = &proj_loop_id;
		call symput("proj_id",strip(id));
		call symput("proj_nm",strip(name));
	run;

	/*Get information on a specific VTA project by it's UUID*/
	filename prj_data temp;
	proc http 
		url="&base_uri/analyticsGateway/projects/&proj_id"
		out=prj_data
		oauth_bearer=sas_services;
	run;

	libname prj_data json;

	/*Identify the data souce used by the project*/
	data _null_;
		set prj_data.providerspecificproperties;
		call symput ("prj_data",strip(textAnalyticsOriginalDataUri));
	run;

	/*Get the list of Pipelines in a Model Studio Project*/
	filename pipes temp;
	proc http 
		url="&base_uri/analyticsGateway/projects/&proj_id/pipelines"
		out=pipes
		oauth_bearer=sas_services;
	run;

	libname pipes json;
	
	/*Create a macro variable for the number of pipelines*/
	data _null_;
		set pipes.root;
		call symput("pipe_cnt",count);
	run;

	/*Loop through every Pipeline*/
	%do pipe_loop_id = 1 %to &pipe_cnt;
		
	/*Create macro varibles for the Pipeline UUID and Name*/
		data _null_;
			set pipes.items;
			if _n_ = &pipe_loop_id;
			call symput("pipe_id",strip(id));
			call symput ("pipe_name",strip(name));
		run;
		
		/*Returns details for a specific Pipeline in a Model Studio Project*/
		filename prj_pipe temp;
		proc http 
			url="&base_uri/analyticsGateway/projects/&proj_id/pipelines/&pipe_id"
			out=prj_pipe
			oauth_bearer=sas_services;
		run;

		libname prj_pipe json;

		/*Finds all the Concept Nodes Used in a Pipeline*/
		proc sql;
			create table concept_nodes as
			select b.p3 as id, b.value as name
			from prj_pipe.alldata (where=(value="concepts" and p4="classification")) a 
			left join prj_pipe.alldata(where=(p4='name')) b
				on a.p3 = b.p3;
		quit;

		/*Creates a macro variable for the number of Concept Nodes in a specific Pipeline*/
		proc sql noprint;
			select count(*) into :concept_node_cnt
			from concept_nodes;
		quit;
		
		/*Loops through all the invididual Concept Nodes in a specific Project/Pipeline */
		%do concept_node_loop_id = 1 %to &concept_node_cnt;
			/*Creates macro variables for the Concept Node UUID and Name*/
			data _null_;
				set concept_nodes;
				if _n_ = &concept_node_loop_id;
				call symput("concept_node_id",strip(id));
				call symput("concept_node_name",strip(name));
			run;

			/*Gets details for a specific Concept Node*/
			filename c_url temp;
			proc http 
				url="&base_uri/analyticsGateway/projects/&proj_id/pipelines/&pipe_id/components/&concept_node_id"
				out=c_url
				oauth_bearer=sas_services;
			run;
	
			libname c_url json;
			/*Creates macro variable for the Concept's Taxonomy Url*/
			data _null_;
				set c_url.links;
				if rel='taxonomyUrl';
				call symput("tax_url",strip(href));
			run;

			/*Creates macro variable identifiying if Predefined Concepts were enabled*/
			data _null_;
				set c_url.componentproperties;
				call symput ("predefined",includePredefined);
			run;
	
			/*Returns the Concept Node's Taxonomy Configuration*/
			filename c_tax_c temp;
			proc http 
				url="&base_uri/&tax_url/configuration"
				out=c_tax_c
				oauth_bearer=sas_services;
			run;

			/*Extract list of all Concept UUID and their Name/Path */
			data tax_c;
				infile c_tax_c truncover;
				input raw $5000.;

				retain concept_id;
				if scan(raw,1,":") = "Concept ID" then concept_id=scan(raw,2,":");
				if scan(raw,1,":") = 'FULLPATH' then fullpath = substr(raw,10);
				drop raw;
				if fullpath ne '';
				if fullpath not in ("nlpPerson:nlpPerson","nlpPlace:nlpPlace","nlpOrganization:nlpOrganization","nlpDate:nlpDate",
					"nlpTime:nlpTime","nlpMoney:nlpMoney","nlpNounGroup:nlpNounGroup","nlpPercent:nlpPercent","nlpMeasure:nlpMeasure");
			run;

			/*Creates macro variable for the number of concepts in the taxonomy*/
			proc sql noprint;
				select count(*) into : concept_cnt
				from tax_c;
			quit;

			/*Loops through all individual Concepts in a specific Taxomnomy*/
			%do concept_loop_id = 1 %to &concept_cnt;
				
				/*Creates macro variable for a concepts UUID & Path   */
				data _null_;
					set tax_c;
					if _n_ = &concept_loop_id;
					call symput ("concept_id",strip(concept_id));
					call symput ("fullpath",strip(fullpath));
				run;	
	
				/*Get the details of a speicific concept*/
				filename c_rule temp;
				proc http 
					url="&base_uri/&tax_url/concepts/&concept_id"
					out=c_rule
					oauth_bearer=sas_services;
				run;
		
				libname c_rule json;

				/*Read the concept rule definition into a SAS table*/
				data casuser.c_rule_temp;
					length json $32000. raw varchar(*);
					infile c_rule truncover recfm=f lrecl=32000 end=eof;
					input @1 json $char32000.;
					retain raw;
					raw=cats(raw,json);
					if eof;
				run;
				
				/*Clean Rule output*/
				data casuser.c_rule;
					set casuser.c_rule_temp;
					length rule varchar(*);
					s=index(raw,'"value":') + 9;
					e=index(raw,'"version":')-2;
					if s ne e and s ne 9 then do;
						rule = substr(raw,s,e-s);
						rule = tranwrd(rule,'\"', '"');
						rule = tranwrd(rule,'\\', '\');
					end;
					rule=unicode(rule);
					keep rule;
				run;

				/*Assign metadata details for a rule*/
				data casuser.c_rule_v2;
					length project_name project_data pipeline_name node_name concept_name fullpath varchar(*);
					merge casuser.c_rule 
							c_rule.root (keep=createdby modifiedby caseInsensitive enabled priority name creationTimeStamp modifiedTimeStamp taxonomyid);
					project_name="&proj_nm";
					project_data = "&prj_data";
					pipeline_name="&pipe_name";
					node_name="&concept_node_name";
					include_predefined = &predefined;
					fullpath="&fullpath";
					concept_name = strip(name);
					
					length taxonomy_id created_by modified_by varchar(*);
					created_by=strip(createdby);
					modified_by=strip(modifiedby);
					taxonomy_id=strip(taxonomyid);
					format create_dt modified_dt datetime.;
					create_dt=input(creationTimeStamp,anydtdtm.);
					modified_dt=input(modifiedTimeStamp,anydtdtm.);
					drop name creationTimeStamp modifiedTimeStamp createdby modifiedby taxonomyid;
				run;

				/*Append concept rule to the export set*/
				data casuser.concept_export (append=yes);
					set casuser.c_rule_v2;
				run;
			%end;
		%end;
	%end;
%end;
%mend;
/* CALL macro program */
%extract_loop;

/*Split Rules into individual rows*/
data casuser.concepts_expand;
	set casuser.concept_export;
	length rule_line varchar(*);
	rule=tranwrd(rule,'\n','0a'x);
	rule=tranwrd(rule,'\r','0d'x);
	rule_line_cnt=countw(rule,'0a0d'x);
	do rule_line_id = 1 to rule_line_cnt;
		rule_line=scan(rule,rule_line_id,'0a0d'x);
		if substr(rule_line,1,1)="#" then type="Comment";
		else type="Rule";
		output;
	end;
	drop rule rule_line_cnt;
run;

/******** SECTION 3 ********/
/* SUBSET source data to observation of interest and move to/keep in CASUSER */
/*************************/
data CASUSER.TEST_OBS;
    set &datacaslib..&datatablename;
    where &unique_row_id_name. = "&unique_row_id_value.";
run;

/******** SECTION 4 ********/
/* CREATE initial model file */
/* capture macvars */
/* create shell */
/*************************/
/* suspend output to Results tab */
ods select none;
/*Create model file of concepts */
data casuser.model / single=yes;
	set casuser.concepts_expand;

	length config varchar(*) r1 r2 rpred r3 varchar(*);
	by concept_name rule_line_id;
	retain custom_concept_id;

	if first.concept_name then custom_concept_id=sum(custom_concept_id,1);

	if first.concept_name then do;
			config = cats("ENABLE:",concept_name);
			output;
			config = cats("FULLPATH:",concept_name,":",concept_name);
			output;
			config = cats("PRIORITY:",concept_name,":",priority);
			output;
			if caseInsensitive = 1 then do;
				config = cats("CASE_INSENSITIVE_MATCH:", concept_name);
				output;
			end;
		end;

		if type="Rule" then do;

            /* capture concept name */
		    r1=scan(rule_line,1,":"); 

            /* find position of first ':' */
            pos1 = find(rule_line, ":");
            if pos1 > 0 then
                r2 = substr(rule_line, pos1 + 1); /* capture string after first ':' */
            else
                r2 = ''; /* Handle cases where the character is not found */

            /* handle predicate_rule */
			config=catx(":", r1, concept_name, r2);
			if r1 = "PREDICATE_RULE" then do;
                /* capture predicate arguments */
                rpred=scan(rule_line,2,":"); 
                /* find position of second ':' */
                pos2 = find(rule_line, ":", pos1 + 1);
                if pos2 > 0 then
                    r3 = substr(rule_line, pos2 + 1); /* capture string after second ':' */
                else
                    r3 = ''; /* Handle cases where the character is not found */
                config=catx(":",r1, cats(concept_name, rpred), r3);
			end;
			if r1 ne " " then output;
		end;
	
		keep config custom_concept_id;
run;

/* find custom_concept_id of target concept to split */
data _null_;
    set CASUSER.model;
    if config = "ENABLE:&search_concept" then do;
        call symputx("custom_concept_num",custom_concept_id);
    end;
run;    

/* find number of rows in concept to keep */
proc sql noprint;
select count(*) into :keeprows from CASUSER.model
where custom_concept_id=&custom_concept_num 
    and scan(config,1,":") in ('ENABLE','FULLPATH','PRIORITY','CASE_INSENSITIVE_MATCH','REMOVE_ITEM') 
;
quit;
%put &=custom_concept_num &=keeprows;

/* CREATE shell to capture macvars */
data params;
    length next_table varchar(*)
    match_cnt1 8
    match_cnt2 8
    nrows2split 8
    keeprows 8
    rowsv1 8
    rowsv2 8
    custom_concept_num 8;
    stop;
run;

/******** SECTION 5 ********/
/* COMPILE recursive macro program */
%macro split_concept(model_split);
    
    %global rowsv1 rowsv2 match_cnt1 match_cnt2 next_table next_table1 next_table2 custom_concept_num;
    %local nrows2split;
    /* find number of rows to split */
    proc sql noprint;
    select count(*) into :nrows2split from CASUSER.&model_split
    where custom_concept_id=&custom_concept_num 
        and scan(config,1,":") not in ('ENABLE','FULLPATH','PRIORITY','CASE_INSENSITIVE_MATCH','REMOVE_ITEM') 
    ;
    quit;
    /* split target concept and count rows */
    /* subset to target concept */
    data CASUSER.CONCEPTRULE_&custom_concept_num;
        set CASUSER.&model_split (where=(custom_concept_id=&custom_concept_num));
    run;
    /* capture max number rows */
    proc sql noprint;
        select count(*) into :max_row 
        from CASUSER.CONCEPTRULE_&custom_concept_num;
    quit;
    /* split keeping top */
    data CASUSER.CONCEPTRULE_V1;
        set CASUSER.CONCEPTRULE_&custom_concept_num; 
        if scan(config,1,":") in ('ENABLE','FULLPATH','PRIORITY','CASE_INSENSITIVE_MATCH','REMOVE_ITEM') or
        _n_ <= (&max_row - (&nrows2split/2)) then output;
    run;    
    /* split keeping bottom */
    data CASUSER.CONCEPTRULE_V2;
        set CASUSER.CONCEPTRULE_&custom_concept_num;
        if scan(config,1,":") in ('ENABLE','FULLPATH','PRIORITY','CASE_INSENSITIVE_MATCH','REMOVE_ITEM') or
        _n_ > (&max_row - (&nrows2split/2)) then output;
    run;
    /* count all rows in each */
    proc sql noprint;
        select count(*) into :rowsv1
        from CASUSER.CONCEPTRULE_V1
    ;
    quit;
    proc sql noprint;
        select count(*) into :rowsv2
        from CASUSER.CONCEPTRULE_V2
    ;
    quit;
    /* create two new model files without target concept, one for each half */
    data CASUSER.&model_split.1;
        set CASUSER.&model_split;
        if custom_concept_id=&custom_concept_num then delete;
    run;
    data CASUSER.&model_split.2;
        set CASUSER.&model_split.1;
    run;
    /* Add back target concept */
    /* first for top */
    data CASUSER.&model_split.1 (append=yes);
		set CASUSER.CONCEPTRULE_V1;
	run;
    /* then for bottom */
    data CASUSER.&model_split.2 (append=yes);
        set CASUSER.CONCEPTRULE_V2;
    run;
    /******** SECTION ********/
    /* Create new model liti files and score data */
    /*************************/
    /* REMOVE liti files if they exist */
    %if %sysfunc(exist(casuser.outli_v1)) %then %do;
        proc delete data=casuser.outli_v1;
        run;
    %end;
    %if %sysfunc(exist(casuser.outli_v2)) %then %do;
        proc delete data=casuser.outli_v2;
        run;
    %end;
    %if %sysfunc(exist(casuser.out_rule_match_v1)) %then %do;
        proc delete data=casuser.out_rule_match_v1;
        run;
    %end;
    %if %sysfunc(exist(casuser.out_rule_match_v2)) %then %do;
        proc delete data=casuser.out_rule_match_v2;
        run;
    %end;
    /* CREATE liti files */
    proc cas;   
        textRuleDevelop.compileConcept /
            casOut={name="outli_v1", replace=TRUE}
            enablePredefined=false
            ruleid="custom_concept_id"
            config="config"
            table={name="&model_split.1"};
        run;
    quit;
    proc cas;   
        textRuleDevelop.compileConcept /
            casOut={name="outli_v2", replace=TRUE}
            enablePredefined=false
            ruleid="custom_concept_id"
            config="config"
            table={name="&model_split.2"};
        run;
    quit;
    /*Score against top  */
    proc cas;
        textRuleScore.applyConcept /
            casOut={name="out_concept1", replace=TRUE}
            docId="&unique_row_id_name"
            factOut={name="out_fact1", replace=TRUE}
            model={name="outli_v1"}
            language='en'
            table={name="test_obs"}
            text="&text_variable_name.";
    run;
    /*Score against bottom  */
    proc cas;
        textRuleScore.applyConcept /
            casOut={name="out_concept2", replace=TRUE}
            docId="&unique_row_id_name"
            factOut={name="out_fact2", replace=TRUE}
            model={name="outli_v2"}
            language='en'
            table={name="test_obs"}
            text="&text_variable_name.";
    run;
    /* find rows that match in top by combining results tables */
    data casuser.new_out_concept1;
    set casuser.out_concept1;
    if upcase(strip(_concept_)) ="&search_concept" and upcase(_match_text_)="&matched_text";
    drop _path_ _start_ _end_ _canonical_form_;
    run;
    /* Rename _FACT_ as _CONCEPT_ as prep for joining results tables */
    data casuser.new_out_fact1;
    set casuser.out_fact1;
    /* if missing(_fact_argument_); */
    if upcase(strip(_fact_)) ="&search_concept" and upcase(_match_text_)="&matched_text";
    drop _result_id_ _fact_argument_ _start_ _end_ _path_;
    rename _fact_=_concept_;
    run;
    /* Create new table of results */
    data casuser.match1;
    set casuser.new_out_concept1 casuser.new_out_fact1;
    run;
    /* count obs that match in top */
    proc sql noprint;
        select count(*) into :match_cnt1
        from casuser.match1
        ;
    quit;
%put &=match_cnt1;
    /* find rows that match in bottom by combining results tables */
    data casuser.new_out_concept2;
    set casuser.out_concept2;
    if upcase(strip(_concept_)) ="&search_concept" and upcase(_match_text_)="&matched_text";
    drop _path_ _start_ _end_ _canonical_form_;
    run;
    /* Rename _FACT_ as _CONCEPT_ as prep for joining results tables */
    data casuser.new_out_fact2;
    set casuser.out_fact2;
    /* if missing(_fact_argument_); */
    if upcase(strip(_fact_)) ="&search_concept" and upcase(_match_text_)="&matched_text";
    drop _result_id_ _fact_argument_ _start_ _end_ _path_;
    rename _fact_=_concept_;
    run;
    /* Create new table of results */
    data casuser.match2;
    set casuser.new_out_concept2 casuser.new_out_fact2;
    run;
    /* count obs that match in bottom */
    proc sql noprint;
        select count(*) into :match_cnt2
        from casuser.match2
        ;
    quit;
    proc sql;
        insert into params (next_table,match_cnt1,match_cnt2,nrows2split,keeprows,rowsv1,rowsv2,custom_concept_num)
        values ("&model_split",&match_cnt1,&match_cnt2,&nrows2split, &keeprows, &rowsv1,&rowsv2,&custom_concept_num)
        ;
    quit;
    /* capture table(s) to propagate */
    data _null_;
        if &match_cnt1 > 0 and &match_cnt2 > 0 and &nrows2split > 1 then do;
            call symputx("next_table1","&model_split.1");
            call execute(cats('%nrstr(%split_concept)', '(&next_table1)'));
            call symputx("next_table2","&model_split.2");
            call execute(cats('%nrstr(%split_concept)', '(&next_table2)'));
        end;
        else do;
            if &match_cnt1 > 0 and &nrows2split > 1 then do;
                call symputx("next_table","&model_split.1");
                call execute(cats('%nrstr(%split_concept)', '(&next_table)'));
            end;
            if &match_cnt2 > 0 and &nrows2split > 1 then do;
                call symputx("next_table","&model_split.2");
                call execute(cats('%nrstr(%split_concept)', '(&next_table)'));
            end;
            else do;
                return; /* Stops execution continues the program */
            end;
        end;
    run;
%mend;
/* CALL recursive macro program */
%split_concept(model);

/******** SECTION 6 ********/
/* output CDR(s) to table and print */
/*************************/
/* reinstate output to Results tab */
ods select all;
/* CREATE table of CDRs that match text */
/* subset to rows with table names containing rules that match */
data params_sub;
    set params;
    if nrows2split = 1;
run;
/* create macvars for extracting rules */
data _null_;
  set params_sub end=last;
  call symputx(catx('_', 'rule', _n_), next_table);
  if last then do;
        call symputx('rule_cnt', _N_);
  end;
run;
%put &=rule_cnt;
data _null_;
    /* check if any matches exist */
    if 0 then set params_sub nobs=n;
    if n=0 then do;
        put "ERROR: Macro variable does not exist";
        put "ERROR: therefore no matches for text string &matched_text in custom concept &search_concept found.";
        abort; /* Stops the current program/step gracefully */
    end;
run;
/* COMPILE macro program */
%macro combine_rules(end);
  data matching_rules (drop= config custom_concept_id);
    length CDR $ 255;
    set %do i = 1 %to &end; 
      CASUSER.&&rule_&i.
    %end;
    ; /* <-- this semicolon ends the SET statement */
    if custom_concept_id = &custom_concept_num;
    if scan(config,1,":") in ('ENABLE','FULLPATH','PRIORITY','CASE_INSENSITIVE_MATCH','REMOVE_ITEM')
    then delete;
    if scan(config,1,":") in ('PREDICATE_RULE','SEQUENCE')
    then CDR = transtrn(config, "&search_concept.", trimn(''));
    else CDR = transtrn(config, "&search_concept.:", trimn(''));
  run;
%mend;
/* CALL macro program */
%combine_rules(&rule_cnt); 

/* PRINT table containing rule(s) */
title;title1;title2;title3;title4;
proc print data=matching_rules noobs;
    title1 j=l "The CDRs in custom concept ==> &search_concept";
    title2 j=l "for the VTA project ==> &sas_project_name";
    title3 j=l "matching the text '&matched_text' in &unique_row_id_name = &unique_row_id_value";
    title4 j=l "is shown below:";
run;
data _null_;
    put 'WARNING: Truncation warning expected.';
    put 'WARNING: Destination width limited.';
run;
/******** SECTION 7 ********/
/******** clean up *******/
/*************************/
/* CLEAR WORK */
proc datasets library=work nolist;
    delete concept: params: proj_filter tax_c;
quit; run;
/* CLEAR CASUSER */
proc datasets library=casuser nolist;
    delete c_rule: concept: error: match: model: new: out: test_obs;
quit; run;
/* CLEAR caslibs */
filename c_rule clear; libname c_rule clear;
filename c_url clear; libname c_url clear;
filename pipes clear; libname pipes clear;
filename prj_data clear; libname prj_data clear;
filename prj_pipe clear; libname prj_pipe clear;
filename projs clear; libname projs clear;

/* end of code */