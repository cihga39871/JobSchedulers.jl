
function set_scheduler_backup(filepath::String = ""; migrate=false, delete_old=false)
    global SCHEDULER_BACKUP_FILE
    if filepath == ""
        @info "Stop scheduler backup."
        delete_old && isfile(SCHEDULER_BACKUP_FILE) && rm(SCHEDULER_BACKUP_FILE, force=true)
        SCHEDULER_BACKUP_FILE = ""
        return SCHEDULER_BACKUP_FILE
    end

    filepath = abspath(filepath)

    if filepath == SCHEDULER_BACKUP_FILE
        return filepath
    end

    if isdir(filepath) || isdirpath(filepath)
        @error "The file path is a directory." filepath
        return SCHEDULER_BACKUP_FILE
    end

    try
        mkpath(dirname(filepath))
    catch
        @error "Cannot set backup file: cannot create directory."
        return SCHEDULER_BACKUP_FILE
    end

    if isfile(filepath)
        recover_backup(filepath)
    end

    if migrate
        if isfile(SCHEDULER_BACKUP_FILE) # old one
            recover_backup(SCHEDULER_BACKUP_FILE)
        end
    end

    delete_old && isfile(SCHEDULER_BACKUP_FILE) && rm(SCHEDULER_BACKUP_FILE, force=true)
    SCHEDULER_BACKUP_FILE = filepath
    return SCHEDULER_BACKUP_FILE
end

function backup_at_exit()
end
