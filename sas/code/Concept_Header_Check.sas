/*******************************************
 * $ID:$lwright
 * 
 * Copyright(c) 2025 SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
 *
 * Name: Concept_Header_Check.sas
 *
 * Purpose: search header in each custom concept for required elements in the header
 *
 * Author(s): Lois Wright (lois.wright@sas.com)
 *
 * Support: SAS(r) US Professional Services
 *
 * Input: text files in local git repository of custom concepts for a model
 *
 * Output: SAS data set of all custom concepts and of the custom concepts without the required information
 *
 * Parameters: user id, git directory, model name, path to directory containing text files (one for each custom concept)
 *
 * Dependencies/Assumptions: Each custom concept in the model of interest has been exported to the git repository
 *
 * Usage: check for required elements in the header of each custom concept
 *
 *******************************************/
/* ASSUMPTION: the program to export all custom concepts to the git repo for model of interest has been executed */
/* specify user id */
%let user_id=lwright;
/* specify name of git repository directory */
%let git_dir=vta_version_control;
/* specify project name */
%let model_name = %str(Color_Project);

/* path to concepts folder */
%let cncpt_folder = /shared/workspace/&user_id./&git_dir./&model_name./_concept_definition_rules/Pipeline 1/Concepts/;

/* get list of filenames from the cncpt_folder recursively */
/* ------------------------------------------------------------------------------------ */
/* from paper, https://www.lexjansen.com/wuss/2012/55.pdf, by Jack Hamilton */
data dirs_found (compress=no);
    length Root $170.;
    root = "&cncpt_folder.";
    output;
run;
data
 dirs_found /* Updated list of directories searched */
 files_found (compress=no); /* Names of files found. */
 keep Path FileName FileType;
 length fref $8 Filename $170 FileType $170;
 /* Read the name of a directory to search. */
 modify dirs_found;
 /* Make a copy of the name, because we might reset root. */
 *Path = tranwrd(root,'\','/');
 Path = root;
 /* For the use and meaning of the FILENAME, DOPEN, DREAD, MOPEN, and */
 /* DCLOSE functions, see the SAS OnlineDocs. */
 rc = filename(fref, path);
 if rc = 0 then
    do;
        did = dopen(fref);
        rc = filename(fref);
    end;
 else
    do;
        length msg $200.;
        msg = sysmsg();
        putlog msg=;
        did = .;
    end;
 if did <= 0
    then
    do;
        putlog 'ERR' 'OR: Unable to open ' Path=;
        return;
 end;
 dnum = dnum(did);
 do i = 1 to dnum;
    filename = dread(did, i);
    fid = mopen(did, filename);
    /* It's not explicitly documented, but the SAS online */
    /* examples show that a return value of 0 from mopen */
    /* means a directory name, and anything else means */
    /* a file name. */
    if fid > 0
    then
    do;
    /* FileType is everything after the last dot. If */
        /* no dot, then no extension. */
        FileType = prxchange('s/.*\.{1,1}(.*)/$1/', 1, filename);
        if filename = filetype then filetype = ' ';
        output files_found;
    end;
    else
    do;
        /* A directory name was found; calculate the complete */
        /* path, and add it to the dirs_found data set, */
        /* where it will be read in the next iteration of this */
        /* data step. */
        root = catt(path, "/", filename);
        output dirs_found;
    end;
  end;
 rc = dclose(did);
run;
/* proc print data=dirs_found; */
/* run; */
/* proc print data=files_found; */
/* run; */
/* ------------------------------------------------------------------------------------ */
proc sort data=files_found;
by filename;
run;
/* filter to text files */
data cpt_fns;
    set files_found;
    if filetype = 'txt' then output;
run;
/* truncate filename to create source concept name, create macvars */
data cpts_src;
	set cpt_fns end=end;
    src_cpt = substr(filename,1,length(filename)-4);
    count+1;
    call symputx('read'||put(count,4.-l),cats(path,"/",filename));
    call symputx('dset'||put(count,4.-l),scan(filename,1,'.'));
	if end then call symputx('max',count);
run;
%put _user_;
/* import each custom text file for the model of interest to search comments in the header */
/* options nomprint nosymbolgen; */
%macro readin;
   %do i=1 %to &max;

      data &&dset&i;
        infile "&&read&i" length=len;
		input line $varying32767. len;
		if missing(line) then delete; /* remove empty lines */
		if find(line,"#") = 1 then output; /* keep only comments for this exercise */
       run;

   %end;
%mend readin;

%readin;

options nonotes; /* max log easily reached so suppress notes */
/* options notes; */
/* options mprint symbolgen; */
/* options nomprint nosymbolgen; */
/* find whether each header contains appropriate information */
/* required info 1) concept name 2) document type 3) purpose 4) created 5) copyright 6) all rights reserved */
/* optional info 1) supports */
%macro hdr_info_exists;
	proc sql;
		create table cncpts_hdr_info /* create empty table to append to */
		(
			cncpt_name varchar length=40 format=$40. label="cncpt_name"
		);
	quit;

		%do j=1 %to &max.; /* for each custom custom concept */

			data out_&j. (drop=line); /* dataset containing header info */
				set &&dset&j;
				cncpt_name = "&&dset&j";
				if find(line, "&&dset&j","i") > 0 then output;
				if find(line,"document type","i") > 0 then output;
				if find(line,"purpose","i") > 0 then output;
				if find(line,"supports","i") > 0 then output;
				if find(line,"created","i") > 0 then output;
				if find(line,"copyright","i") > 0 then output;
				if find(line,"all rights reserved","i") > 0 then output;
			run;

			data _NULL_; /* create macvar of obs in previous data set */
			    IF 0 THEN SET out_&j. NOBS=N;
				CALL SYMPUTX('NOBS', N);
				STOP;
			run;

			%if &NOBS. ge 6 %then %do; /* create list that passed criteria */
				PROC SQL;
					create table cncpt as
					select distinct cncpt_name length=40 format=$40.
					from out_&j.;
				QUIT;
				proc append base=cncpts_hdr_info data=cncpt;
				run;
				proc sql;
					drop table cncpt;
				quit;

			%end;

			proc sql;
				drop table out_&j.; /* delete out data set */
			quit;

		%end; /* repeat for each custom concept */

%mend hdr_info_exists;
%hdr_info_exists;

/* list of distinct concepts with appropriate header info */
proc sql;
	create table cncpts_verify as
	select distinct cncpt_name
	from cncpts_hdr_info
;
quit;

/* substract concepts with hdr info from full list of distinct concepts to yield concepts without hdr info */
proc sql;
	create table cncpts_need_hdr_info as
	select src_cpt as custom_concept_name
	from cpts_src
	except
	select cncpt_name as custom_concept_name
	from cncpts_verify 
;
quit;

%macro print_concepts;
    %let doesItExist=NO; 
    data _null_; 
        set WORK.CNCPTS_NEED_HDR_INFO; 
        call symput("doesItExist","YES"); 
        stop; 
    run; 
    %put &=doesItExist;
    %if &doesItExist. = YES %then %do;
        proc print data=cncpts_need_hdr_info noobs;
        title1;
        title1 "Concepts in &model_name that need header information.";
        run;
    %end;
    %else %do;
        data _null_;
            file print;
            put "Note: WORK.CNCPTS_NEED_HDR_INFO contains no observations.";
            put "      Therefore model passes peer review for header check.";
        run;
    %end;
%mend print_concepts;
%print_concepts;

/* end of code */
