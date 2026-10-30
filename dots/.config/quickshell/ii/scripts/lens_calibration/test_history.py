from history import History, purpose_group


def test_history_persists_and_separates_folders(tmp_path):
    projects = tmp_path/'projects'; projects.mkdir()
    images = tmp_path/'images'; images.mkdir()
    project = projects/'Room.lenscap'; project.write_text('{}')
    history = History(tmp_path/'state/recent.json')
    history.update(purpose_group('save'), [project.as_uri()], project=True)
    history.update(purpose_group('open'), [images/'snapshot.png'])
    reopened = History(history.filename)
    assert reopened.projects() == [str(project)]
    assert reopened.folder(purpose_group('load'), tmp_path) == str(projects)
    assert reopened.folder(purpose_group('add_images'), tmp_path) == str(images)


def test_recent_order_deduplication_and_missing_paths(tmp_path):
    history = History(tmp_path/'state.json')
    files = [tmp_path/f'{i}.lensproject' for i in range(15)]
    for file in files:
        file.write_text('{}'); history.update('project', [file], project=True)
    assert len(history.projects()) == 12
    history.update('project', [files[4]], project=True)
    assert history.projects()[0] == str(files[4])
    assert len(history.projects()) == 12
    files[4].unlink()
    assert str(files[4]) not in history.projects()
    assert history.folder('nonexistent', tmp_path) == str(tmp_path)


def test_invalid_history_and_removed_folder_fall_back(tmp_path):
    filename = tmp_path/'recent.json'; filename.write_text('broken')
    history = History(filename)
    assert history.projects() == []
    assert history.folder('project', tmp_path) == str(tmp_path)
    filename.write_text('{"projects": false, "folders": []}')
    assert history.projects() == []
    history.update('project', [tmp_path/'missing/file.lensproject'], project=True)
    assert history.projects() == []
    assert history.folder('project', tmp_path) == str(tmp_path)
