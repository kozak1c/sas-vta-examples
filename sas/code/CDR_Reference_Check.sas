/*******************************************
 * $ID:$lwright
 * 
 * Copyright(c) 2025 SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
 *
 * Name: CDR_Reference_Check.sas
 *
 * Purpose: find source and target concepts in a model
 *
 * Author(s): Lois Wright (lois.wright@sas.com)
 *
 * Support: SAS(r) US Professional Services
 *
 * Input: text files in local git repository of custom concepts for a model
 *
 * Output: SAS data set of all source concepts, the target concepts referenced within each source
 *			concept, and the number of times it is referenced
 *
 * Parameters: user id, git directory, model name, path to directory containing text files (one for each custom concept)
 *
 * Dependencies/Assumptions: Each custom concept in the model of interest has been exported to the git repository
 *
 * Usage: determine whether a stale custom concept exists in the model of interest
 *
 *******************************************/
/* ASSUMPTION: the program to export all custom concepts to the git repo for model of interest has been executed */
/* specify user id */
%let user_id=lwright;
/* specify name of git repository directory */
%let git_dir=vta_version_control;
/* specify project name */
%let model_name = %str(Color_Project);

/* path to concepts directory */
%let cncpt_folder = /shared/workspace/&user_id./&git_dir./&model_name./_concept_definition_rules/Pipeline 1/Concepts/;

/* ------------------------------------------------------------------------------------ */
/* get list of filenames from the cncpt_folder recursively */
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
*%put _user_;
/* import each custom concept text file for the model of interest to search each line for a concept */
/* options nomprint nosymbolgen; */
%macro readin;
   %do i=1 %to &max;

      data &&dset&i;
        infile "&&read&i" length=len;
		input line $varying32767. len;
		if missing(line) then delete; /* remove empty lines */
		if find(line,"#") = 1 then delete; /* remove comments */
       run;

   %end;
%mend readin;

%readin;

options nonotes; /* max log easily reached so suppress notes */
/* options notes; */
/* options mprint symbolgen; */
/* options nomprint nosymbolgen; */
/* find whether each dset contains a target concept */
%macro trg_cpt_exists;
	proc sql;
		create table cnt_trg_cncpts /* create empty table to append to */
		(
			src_cncpt varchar length=40 format=$40. label="src_cncpt"
			,trg_cncpt varchar length=40 format=$40. label="trg_cncpt"
			,cnt_trg num length=8 format=best12. label="cnt_trg"
		);
	quit;
	%do i=1 %to &max.; /* for each source custom concept */

		%do j=1 %to &max.; /* for each target custom concept */

			data out_&i._&j. (drop=line); /* dataset containing source & target concepts if target found */
				set &&dset&i;
				format src_cncpt $40. trg_cncpt $40.;
				src_cncpt = "&&dset&i";
				trg_cncpt = "&&dset&j";
				if find(line, "&&dset&j") > 0 then output;
			run;
  
			data _NULL_; /* create macvar of obs in previous data set */
			    IF 0 THEN SET out_&i._&j. NOBS=N;
				CALL SYMPUTX('NOBS', N);
				STOP;
			run;

			%if &NOBS. > 0 %then %do; /* create count of concepts, append, delete */
				PROC SQL;
					create table cnt as
					select distinct src_cncpt length=40 format=$40.
						,trg_cncpt length=40 format=$40.
						,count(trg_cncpt) as cnt_trg length=8 format=best12.
					from out_&i._&j.;
				QUIT;
				proc append base=cnt_trg_cncpts data=cnt;
				run;
				proc sql;
					drop table cnt;
				quit;

			%end;

			proc sql;
				drop table out_&i._&j.; /* delete first data set */
			quit;

		%end; /* repeat for each target concept */

	%end; /* repeat for each source concept */
%mend trg_cpt_exists;
%trg_cpt_exists;

/* list of distinct concepts referenced */
proc sql;
	create table cncpts_verify as
	select distinct trg_cncpt
	from cnt_trg_cncpts
;
quit;

/* substract referenced concepts from full list of distinct concepts to yield unreferenced concepts */
proc sql;
	create table cncpts_not_ref as
	select src_cpt as custom_concept_name
	from cpts_src
	except
	select trg_cncpt as custom_concept_name
	from cncpts_verify 
;
quit;

/* list of concepts self referenced only */
proc sql;
	create table cncpts_self_only as
	select distinct trg_cncpt
	from cnt_trg_cncpts
	where cnt_trg = 1 and src_cncpt=trg_cncpt 
		and trg_cncpt not in 
		(select trg_cncpt from cnt_trg_cncpts where cnt_trg ge 1
		and src_cncpt ne trg_cncpt )
;
quit;

%macro print_concepts;
    %let doesItExist=NO; 
    data _null_; 
        set WORK.cncpts_not_ref; 
        call symput("doesItExist","YES"); 
        stop; 
    run; 
    %put &=doesItExist;
    %if &doesItExist. = YES %then %do;
        proc print data=cncpts_not_ref noobs;
        title1;
        title1 "Concepts in &model_name that are not referenced.";
        run;
    %end;
    %else %do;
        data _null_;
            file print;
            put "WORK.CNCPTS_NOT_REF contains no observations.";
            put "Therefore no stale concepts in &model_name.";
        run;
    %end;
%mend print_concepts;

%print_concepts;

/* end of code */