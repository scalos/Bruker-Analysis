function openDir(path)
    system(sprintf("open %s",strrep(path,' ','\ ')))
end