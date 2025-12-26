rows = [
    {"name": "Marc", "profession": "Software engineer", "nationality": "Switzerland"},
    {"name": "Marc", "profession": "Software engineer", "nationality": "Switzerland"},
]


def create_html_table(rows):
    if not rows:
        return ""

    headers = list(rows[0].keys())

    html = "<table style='width:100%'>\n"
    html += "  <thead style='background-color:#f2f2f2'>\n"
    html += "    <tr >\n"
    for header in headers:
        html += f"      <th >{header}</th>\n"
    html += "    </tr>\n"
    html += "  </thead>\n"
    html += "  <tbody>\n"
    for i, row in enumerate(rows):
        if i % 2 == 0:
            row_style = "background-color:#f2f2f2;"
        else:
            row_style = ""
        html += f"    <tr style='{row_style}'>\n"
        for header in headers:
            html += f"      <td>{row[header]}</td>\n"
        html += "    </tr>\n"
    html += "  </tbody>\n"
    html += "</table>"

    return html
