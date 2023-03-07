import sys
import json
from os import path
from jinja2 import Environment, FileSystemLoader


def render_html(data, cwd, tmplt_file, output_file):
    environment = Environment(loader=FileSystemLoader(cwd))
    template = environment.get_template(tmplt_file)
    content = template.render(data)
    with open(output_file, mode='w', encoding='utf-8') as f:
        f.write(content)
        print(f"... wrote {output_file}")


def main(cwd, data_json, tmplt_file, output_file):
    # assert file paths
    for file_path in [
            data_json,
            path.join(cwd, tmplt_file),
    ]:
        assert path.isfile(file_path), f'File not fount: {file_path}'

    # get data and render html file
    data = {}
    with open(data_json, 'r') as f:
        data = json.load(f)

    render_html(data, cwd, tmplt_file, output_file)


if __name__ == "__main__":
    # parsing and verifying arguments
    params = {}
    for p in sys.argv[1:]:
        p_split = p.split('=')
        params[p_split[0]] = p_split[-1]

    pkg_type = params.get('--type')
    data_json = params.get('--in', '')
    output_file = params.get('--out', '')

    conditions = [
        pkg_type in ['pip', 'npm'],
        path.isfile(data_json),
        path.isdir(path.dirname(output_file)),
    ]
    if not all(conditions):
        print(f"Wrong or missing parameters: {params}")
        sys.exit(1)

    # setting working directory and starting
    cwd = path.dirname(path.abspath(__file__))
    tmplt_file = f"{pkg_type}.html.j2"
    main(cwd, data_json, tmplt_file, output_file)
    sys.exit(0)
